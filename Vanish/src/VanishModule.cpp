#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <cstring>

namespace {

using lua_State = struct lua_State;
using lua_CFunction = int(__cdecl*)(lua_State*);

using fn_createtable  = void(__cdecl*)(lua_State*, int, int);
using fn_pushcclosure = void(__cdecl*)(lua_State*, lua_CFunction, int);
using fn_setfield     = void(__cdecl*)(lua_State*, int, char const*);
using fn_pushvalue    = void(__cdecl*)(lua_State*, int);
using fn_pushstring   = void(__cdecl*)(lua_State*, char const*);
using fn_tonumber     = double(__cdecl*)(lua_State*, int);
using fn_tolstring    = char const*(__cdecl*)(lua_State*, int, std::size_t*);

constexpr int kGlobalsIndex = -10002;

struct LuaApi {
    fn_createtable  createtable  = nullptr;
    fn_pushcclosure pushcclosure = nullptr;
    fn_setfield     setfield     = nullptr;
    fn_pushvalue    pushvalue    = nullptr;
    fn_pushstring   pushstring   = nullptr;
    fn_tonumber     tonumber     = nullptr;
    fn_tolstring    tolstring    = nullptr;

    bool ready() const {
        return createtable && pushcclosure && setfield && pushvalue
            && pushstring && tonumber && tolstring;
    }
};

LuaApi g_lua {};

constexpr std::uintptr_t kEntityName       = 0x07C;
constexpr std::uintptr_t kEntityTargetType = 0x0EE;
constexpr std::uintptr_t kEntityRender1    = 0x124;
constexpr std::uint32_t  kHideBit          = 0x1000;

constexpr unsigned char kTargetTypePlayer = 0;

constexpr DWORD kMaxIndex = 0x900;
constexpr int   kMaxNames = 256;
constexpr int   kNameLen  = 24;

volatile LONG g_mode = 0;

char g_names[kMaxNames][kNameLen] {};
int  g_name_count = 0;

bool g_exempt[kMaxIndex] {};
bool g_hidden[kMaxIndex] {};

volatile LONG g_self_index = 0;

CRITICAL_SECTION g_lock;
bool g_lock_ready = false;

HANDLE g_thread = nullptr;
volatile LONG g_running = 0;
volatile LONG g_unloading = 0;

struct Region {
    std::uintptr_t base = 0;
    std::size_t    size = 0;
    bool           ok   = false;
};

constexpr int kRegionSlots = 24;
Region g_regions[kRegionSlots] {};
int    g_region_next = 0;
DWORD  g_region_stamp = 0;

bool page_writable(DWORD protect) {
    if (protect & PAGE_GUARD) {
        return false;
    }

    return (protect & (PAGE_READWRITE | PAGE_WRITECOPY
        | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) != 0;
}

void flush_regions() {
    for (int i = 0; i < kRegionSlots; ++i) {
        g_regions[i] = Region {};
    }

    g_region_next = 0;
}

// Cached so the sweep is not one VirtualQuery per entity per pass. Flushed
// every second so memory freed on a zone change is never trusted for long.
bool writable(std::uintptr_t address, std::size_t size) {
    if (address < 0x10000 || address + size < address) {
        return false;
    }

    DWORD const now = GetTickCount();
    if (now - g_region_stamp > 1000) {
        g_region_stamp = now;
        flush_regions();
    }

    for (int i = 0; i < kRegionSlots; ++i) {
        Region const& r = g_regions[i];
        if (r.base != 0 && address >= r.base && address + size <= r.base + r.size) {
            return r.ok;
        }
    }

    MEMORY_BASIC_INFORMATION info {};
    if (VirtualQuery(reinterpret_cast<void const*>(address), &info, sizeof(info)) == 0) {
        return false;
    }

    Region entry {};
    entry.base = reinterpret_cast<std::uintptr_t>(info.BaseAddress);
    entry.size = info.RegionSize;
    entry.ok = info.State == MEM_COMMIT && page_writable(info.Protect);

    g_regions[g_region_next] = entry;
    g_region_next = (g_region_next + 1) % kRegionSlots;

    return entry.ok && address + size <= entry.base + entry.size;
}

bool module_range(char const* name, std::uintptr_t& base) {
    base = 0;

    HMODULE module = GetModuleHandleA(name);
    if (!module) {
        return false;
    }

    base = reinterpret_cast<std::uintptr_t>(module);
    auto const* dos = reinterpret_cast<IMAGE_DOS_HEADER const*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
        return false;
    }

    auto const* nt = reinterpret_cast<IMAGE_NT_HEADERS32 const*>(
        base + static_cast<std::uintptr_t>(dos->e_lfanew));
    if (nt->Signature != IMAGE_NT_SIGNATURE) {
        return false;
    }

    return nt->OptionalHeader.SizeOfImage != 0;
}

std::uintptr_t scan_module(char const* name, unsigned char const* pattern,
    char const* mask, std::size_t length) {
    std::uintptr_t base = 0;
    if (!module_range(name, base)) {
        return 0;
    }

    auto const* dos = reinterpret_cast<IMAGE_DOS_HEADER const*>(base);
    auto const* nt = reinterpret_cast<IMAGE_NT_HEADERS32 const*>(
        base + static_cast<std::uintptr_t>(dos->e_lfanew));

    auto const* section = IMAGE_FIRST_SECTION(nt);
    for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section) {
        if ((section->Characteristics & IMAGE_SCN_MEM_EXECUTE) == 0) {
            continue;
        }

        std::uintptr_t const start = base + section->VirtualAddress;
        std::size_t const span = section->Misc.VirtualSize;
        if (span <= length) {
            continue;
        }

        auto const* bytes = reinterpret_cast<unsigned char const*>(start);
        for (std::size_t offset = 0; offset + length <= span; ++offset) {
            bool hit = true;
            for (std::size_t j = 0; j < length; ++j) {
                if (mask[j] != '?' && bytes[offset + j] != pattern[j]) {
                    hit = false;
                    break;
                }
            }

            if (hit) {
                return start + offset;
            }
        }
    }

    return 0;
}

std::uintptr_t g_entity_array = 0;
bool g_entity_array_resolved = false;

// mov edx,[esi+0xC] / mov eax,[edx+ebp] / mov eax,[eax*4+imm32]
// The trailing imm32 is the array base itself, not a pointer to it.
std::uintptr_t entity_array() {
    if (g_entity_array_resolved) {
        return g_entity_array;
    }

    g_entity_array_resolved = true;

    static unsigned char const pattern[] = {
        0x8B, 0x56, 0x0C, 0x8B, 0x04, 0x2A, 0x8B, 0x04, 0x85,
    };
    static char const mask[] = "xxxxxxxxx";

    std::uintptr_t const match = scan_module("FFXiMain.dll", pattern, mask, sizeof(pattern));
    if (match == 0) {
        return 0;
    }

    std::uint32_t base = 0;
    std::memcpy(&base, reinterpret_cast<void const*>(match + sizeof(pattern)), sizeof(base));
    if (!writable(base, sizeof(std::uintptr_t) * kMaxIndex)) {
        return 0;
    }

    g_entity_array = base;
    return g_entity_array;
}

char lower_ascii(char c) {
    return (c >= 'A' && c <= 'Z') ? static_cast<char>(c + 32) : c;
}

void read_name(std::uintptr_t entity, char* out) {
    std::memset(out, 0, kNameLen);

    auto const* src = reinterpret_cast<char const*>(entity + kEntityName);
    for (int i = 0; i < kNameLen - 1; ++i) {
        char const c = src[i];
        if (c == '\0') {
            break;
        }

        out[i] = lower_ascii(c);
    }
}

bool name_listed(char const* lowered) {
    for (int i = 0; i < g_name_count; ++i) {
        if (std::strcmp(g_names[i], lowered) == 0) {
            return true;
        }
    }

    return false;
}

// Only ever clears the bit on entities this module set it on.
void apply(std::uintptr_t entity, DWORD index, bool hide) {
    auto* flags = reinterpret_cast<volatile std::uint32_t*>(entity + kEntityRender1);
    std::uint32_t const value = *flags;

    if (hide) {
        if ((value & kHideBit) == 0) {
            *flags = value | kHideBit;
        }

        g_hidden[index] = true;
        return;
    }

    if (g_hidden[index]) {
        if ((value & kHideBit) != 0) {
            *flags = value & ~kHideBit;
        }

        g_hidden[index] = false;
    }
}

void sweep() {
    std::uintptr_t const base = entity_array();
    if (base == 0) {
        return;
    }

    LONG const mode = g_mode;
    LONG const self = g_self_index;

    EnterCriticalSection(&g_lock);

    for (DWORD index = 1; index < kMaxIndex; ++index) {
        std::uintptr_t entity = 0;
        std::memcpy(&entity,
            reinterpret_cast<void const*>(base + static_cast<std::uintptr_t>(index) * 4),
            sizeof(entity));

        if (entity < 0x10000) {
            g_hidden[index] = false;
            continue;
        }

        if (!writable(entity, 0x200)) {
            continue;
        }

        unsigned char const type =
            *reinterpret_cast<unsigned char const*>(entity + kEntityTargetType);

        if (type != kTargetTypePlayer) {
            apply(entity, index, false);
            continue;
        }

        bool hide = false;

        if (mode != 0 && !g_exempt[index] && static_cast<LONG>(index) != self) {
            char name[kNameLen];
            read_name(entity, name);

            if (name[0] == '\0') {
                hide = mode == 2;
            } else {
                bool const listed = name_listed(name);
                hide = mode == 1 ? listed : !listed;
            }
        }

        apply(entity, index, hide);
    }

    LeaveCriticalSection(&g_lock);
}

void restore_all() {
    std::uintptr_t const base = entity_array();
    if (base == 0) {
        return;
    }

    EnterCriticalSection(&g_lock);

    for (DWORD index = 1; index < kMaxIndex; ++index) {
        if (!g_hidden[index]) {
            continue;
        }

        std::uintptr_t entity = 0;
        std::memcpy(&entity,
            reinterpret_cast<void const*>(base + static_cast<std::uintptr_t>(index) * 4),
            sizeof(entity));

        if (entity >= 0x10000 && writable(entity, 0x200)) {
            auto* flags = reinterpret_cast<volatile std::uint32_t*>(entity + kEntityRender1);
            *flags = *flags & ~kHideBit;
        }

        g_hidden[index] = false;
    }

    LeaveCriticalSection(&g_lock);
}

DWORD WINAPI worker(LPVOID) {
    while (InterlockedCompareExchange(&g_running, 1, 1) == 1
        && InterlockedCompareExchange(&g_unloading, 0, 0) == 0) {
        sweep();
        Sleep(10);
    }

    return 0;
}

char const* arg_string(lua_State* L, int index) {
    std::size_t length = 0;
    return g_lua.tolstring(L, index, &length);
}

void set_names(char const* csv) {
    EnterCriticalSection(&g_lock);

    g_name_count = 0;
    std::memset(g_names, 0, sizeof(g_names));

    if (csv != nullptr) {
        int out = 0;

        for (char const* cursor = csv; *cursor != '\0' && g_name_count < kMaxNames; ++cursor) {
            if (*cursor == ',') {
                if (out > 0) {
                    ++g_name_count;
                    out = 0;
                }

                continue;
            }

            if (out < kNameLen - 1) {
                g_names[g_name_count][out] = lower_ascii(*cursor);
                ++out;
            }
        }

        if (out > 0 && g_name_count < kMaxNames) {
            ++g_name_count;
        }
    }

    LeaveCriticalSection(&g_lock);
}

void set_exempt(char const* csv) {
    EnterCriticalSection(&g_lock);

    std::memset(g_exempt, 0, sizeof(g_exempt));

    if (csv != nullptr) {
        DWORD value = 0;
        bool have = false;

        for (char const* cursor = csv; ; ++cursor) {
            if (*cursor >= '0' && *cursor <= '9') {
                value = value * 10 + static_cast<DWORD>(*cursor - '0');
                have = true;
                continue;
            }

            if (have) {
                if (value < kMaxIndex) {
                    g_exempt[value] = true;
                }

                value = 0;
                have = false;
            }

            if (*cursor == '\0') {
                break;
            }
        }
    }

    LeaveCriticalSection(&g_lock);
}

int __cdecl lua_start(lua_State* L) {
    char status[96] {};

    if (entity_array() == 0) {
        g_lua.pushstring(L, "entity array not found");
        return 1;
    }

    if (InterlockedCompareExchange(&g_running, 1, 0) == 0) {
        g_thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr);
        if (g_thread == nullptr) {
            InterlockedExchange(&g_running, 0);
            g_lua.pushstring(L, "worker thread failed to start");
            return 1;
        }
    }

    std::snprintf(status, sizeof(status), "loaded (entity array 0x%08X)",
        static_cast<unsigned>(entity_array()));
    g_lua.pushstring(L, status);
    return 1;
}

int __cdecl lua_stop(lua_State*) {
    if (InterlockedExchange(&g_running, 0) == 1 && g_thread != nullptr) {
        WaitForSingleObject(g_thread, 500);
        CloseHandle(g_thread);
        g_thread = nullptr;
    }

    InterlockedExchange(&g_mode, 0);
    restore_all();

    return 0;
}

int __cdecl lua_mode(lua_State* L) {
    LONG const requested = static_cast<LONG>(g_lua.tonumber(L, 1));

    if (requested == 1 || requested == 2) {
        InterlockedExchange(&g_mode, requested);
    }

    return 0;
}

int __cdecl lua_names(lua_State* L) {
    set_names(arg_string(L, 1));
    return 0;
}

int __cdecl lua_exempt(lua_State* L) {
    set_exempt(arg_string(L, 1));
    InterlockedExchange(&g_self_index, static_cast<LONG>(g_lua.tonumber(L, 2)));
    return 0;
}

bool bind_lua() {
    if (g_lua.ready()) {
        return true;
    }

    static char const* const hosts[] = {"LuaCore.dll", "lua51.dll", "lua5.1.dll"};
    for (char const* host : hosts) {
        HMODULE module = GetModuleHandleA(host);
        if (!module) {
            continue;
        }

        auto load = [module](char const* name) -> void* {
            return reinterpret_cast<void*>(GetProcAddress(module, name));
        };

        g_lua.createtable  = reinterpret_cast<fn_createtable>(load("lua_createtable"));
        g_lua.pushcclosure = reinterpret_cast<fn_pushcclosure>(load("lua_pushcclosure"));
        g_lua.setfield     = reinterpret_cast<fn_setfield>(load("lua_setfield"));
        g_lua.pushvalue    = reinterpret_cast<fn_pushvalue>(load("lua_pushvalue"));
        g_lua.pushstring   = reinterpret_cast<fn_pushstring>(load("lua_pushstring"));
        g_lua.tonumber     = reinterpret_cast<fn_tonumber>(load("lua_tonumber"));
        g_lua.tolstring    = reinterpret_cast<fn_tolstring>(load("lua_tolstring"));

        if (g_lua.ready()) {
            return true;
        }
    }

    return false;
}

}  // namespace

extern "C" __declspec(dllexport) int __cdecl luaopen__Vanish(lua_State* L) {
    if (!bind_lua()) {
        return 0;
    }

    if (!g_lock_ready) {
        InitializeCriticalSection(&g_lock);
        g_lock_ready = true;
    }

    g_lua.createtable(L, 0, 5);

    struct Entry {
        char const* name;
        lua_CFunction fn;
    };

    static Entry const entries[] = {
        {"start",  lua_start},
        {"stop",   lua_stop},
        {"mode",   lua_mode},
        {"names",  lua_names},
        {"exempt", lua_exempt},
    };

    for (Entry const& entry : entries) {
        g_lua.pushcclosure(L, entry.fn, 0);
        g_lua.setfield(L, -2, entry.name);
    }

    g_lua.pushvalue(L, -1);
    g_lua.setfield(L, kGlobalsIndex, "_Vanish");
    return 1;
}

BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_DETACH) {
        // Loader lock is held here, so the worker cannot be joined. The addon's
        // unload handler calls _Vanish.stop() for the orderly path.
        InterlockedExchange(&g_unloading, 1);
        InterlockedExchange(&g_running, 0);
    }

    return TRUE;
}
