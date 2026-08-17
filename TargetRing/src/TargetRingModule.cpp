#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d8.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

namespace {

using lua_State = struct lua_State;
using lua_CFunction = int(__cdecl*)(lua_State*);

using fn_createtable = void(__cdecl*)(lua_State*, int, int);
using fn_pushcclosure = void(__cdecl*)(lua_State*, lua_CFunction, int);
using fn_setfield = void(__cdecl*)(lua_State*, int, char const*);
using fn_pushvalue = void(__cdecl*)(lua_State*, int);
using fn_pushstring = void(__cdecl*)(lua_State*, char const*);
using fn_gettop = int(__cdecl*)(lua_State*);
using fn_tonumber = double(__cdecl*)(lua_State*, int);

constexpr int kGlobalsIndex = -10002;

struct LuaApi {
    fn_createtable createtable = nullptr;
    fn_pushcclosure pushcclosure = nullptr;
    fn_setfield setfield = nullptr;
    fn_pushvalue pushvalue = nullptr;
    fn_pushstring pushstring = nullptr;
    fn_gettop gettop = nullptr;
    fn_tonumber tonumber = nullptr;

    bool ready() const {
        return createtable && pushcclosure && setfield && pushvalue
            && pushstring && gettop && tonumber;
    }
};

LuaApi g_lua {};
HMODULE g_self = nullptr;

struct Position {
    float east = 0.0f;
    float north = 0.0f;
    float height = 0.0f;
};

struct DrawVertex {
    float x;
    float y;
    float z;
    float rhw;
    DWORD color;
};

struct MotionState {
    Position pos {};
    Position velocity {};
    DWORD last_ms = 0;
    bool initialized = false;
};

struct Ring {
    DWORD index = 0;
    Position centre;
    float radius = 0.0f;
    DWORD color = 0;
    bool active = false;
};

constexpr int kMaxRings = 64;
constexpr int ring_slices_ = 48;
constexpr int max_batch_vertices_ = 8192;
constexpr float kFadeSpan = 0.55f;
constexpr float kGroundClearance = 0.05f;
constexpr float kSmoothBlend = 0.72f;
constexpr DWORD kMaxIndex = 0x900;
// entity+0x004 is the client's *predicted* position and leads the mesh while a
// mob runs. The display object's nameplate base is where the model is actually
// drawn, so that is preferred and 0x004 is only a fallback for unrendered
// entities. Layout per Windower's libraries/memory/types.lua.
constexpr std::uintptr_t kEntityDisplayPos = 0x004;
constexpr std::uintptr_t kEntityDisplayPtr = 0x0A0;
constexpr std::uintptr_t kDisplayNameplateBase = 0x678;
constexpr std::size_t kPrologueBytes = 9;

Ring g_rings[kMaxRings] {};
MotionState g_motion[kMaxIndex] {};
volatile bool g_samples_fresh = false;
volatile int g_ring_count = 0;

using draw_scene_fn = void(__fastcall*)(void*, void*);
draw_scene_fn g_trampoline = nullptr;
std::uintptr_t g_draw_scene = 0;
unsigned char g_original_bytes[kPrologueBytes] {};
volatile bool g_hooked = false;
volatile unsigned long g_frames = 0;
volatile unsigned long g_draws = 0;
std::uintptr_t g_renderer = 0;
std::uintptr_t g_device = 0;
volatile bool g_discovery_done = false;
char g_status[192] = "idle";

bool page_readable(DWORD protect) {
    if (protect & (PAGE_GUARD | PAGE_NOACCESS)) {
        return false;
    }

    switch (protect & 0xFF) {
    case PAGE_READONLY:
    case PAGE_READWRITE:
    case PAGE_WRITECOPY:
    case PAGE_EXECUTE_READ:
    case PAGE_EXECUTE_READWRITE:
    case PAGE_EXECUTE_WRITECOPY:
        return true;
    default:
        return false;
    }
}

bool span_readable(std::uintptr_t address, std::size_t size) {
    if (address == 0 || size == 0) {
        return false;
    }

    MEMORY_BASIC_INFORMATION region {};
    if (!VirtualQuery(reinterpret_cast<void const*>(address), &region, sizeof(region))) {
        return false;
    }

    if (region.State != MEM_COMMIT || !page_readable(region.Protect)) {
        return false;
    }

    std::uintptr_t const low = reinterpret_cast<std::uintptr_t>(region.BaseAddress);
    return address >= low && address + size <= low + region.RegionSize;
}

bool module_range(char const* name, std::uintptr_t& base, std::size_t& size) {
    base = 0;
    size = 0;

    HMODULE module = GetModuleHandleA(name);
    if (!module) {
        return false;
    }

    base = reinterpret_cast<std::uintptr_t>(module);
    if (!span_readable(base, sizeof(IMAGE_DOS_HEADER))) {
        return false;
    }

    auto const* dos = reinterpret_cast<IMAGE_DOS_HEADER const*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
        return false;
    }

    std::uintptr_t const nt_address = base + static_cast<std::uintptr_t>(dos->e_lfanew);
    if (!span_readable(nt_address, sizeof(IMAGE_NT_HEADERS32))) {
        return false;
    }

    auto const* nt = reinterpret_cast<IMAGE_NT_HEADERS32 const*>(nt_address);
    if (nt->Signature != IMAGE_NT_SIGNATURE) {
        return false;
    }

    size = nt->OptionalHeader.SizeOfImage;
    return size != 0;
}

std::uintptr_t scan_module(char const* name, unsigned char const* pattern,
    char const* mask, std::size_t length) {
    std::uintptr_t base = 0;
    std::size_t image = 0;
    if (!module_range(name, base, image)) {
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
        if (span <= length || !span_readable(start, span)) {
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

void* vtable_slot(std::uintptr_t object, int index) {
    if (!span_readable(object, sizeof(std::uintptr_t))) {
        return nullptr;
    }

    std::uintptr_t vtable = 0;
    std::memcpy(&vtable, reinterpret_cast<void const*>(object), sizeof(vtable));

    std::uintptr_t const entry = vtable + static_cast<std::uintptr_t>(index) * sizeof(std::uintptr_t);
    if (!span_readable(entry, sizeof(std::uintptr_t))) {
        return nullptr;
    }

    std::uintptr_t address = 0;
    std::memcpy(&address, reinterpret_cast<void const*>(entry), sizeof(address));
    return reinterpret_cast<void*>(address);
}

using fn_get_device = long(__stdcall*)(void*, void**);
using fn_release = unsigned long(__stdcall*)(void*);
using fn_get_transform = long(__stdcall*)(void*, DWORD, D3DMATRIX*);
using fn_get_viewport = long(__stdcall*)(void*, D3DVIEWPORT8*);
using fn_get_render_state = long(__stdcall*)(void*, DWORD, DWORD*);
using fn_set_render_state = long(__stdcall*)(void*, DWORD, DWORD);
using fn_get_vertex_shader = long(__stdcall*)(void*, DWORD*);
using fn_set_vertex_shader = long(__stdcall*)(void*, DWORD);
using fn_get_texture = long(__stdcall*)(void*, DWORD, void**);
using fn_set_texture = long(__stdcall*)(void*, DWORD, void*);
using fn_draw_up = long(__stdcall*)(void*, DWORD, unsigned, void const*, unsigned);

void* d3d_device_ = nullptr;

long dev_GetTransform(DWORD state, D3DMATRIX* out) {
    auto f = reinterpret_cast<fn_get_transform>(vtable_slot(g_device, 38));
    return f ? f(d3d_device_, state, out) : -1;
}

long dev_GetViewport(D3DVIEWPORT8* out) {
    auto f = reinterpret_cast<fn_get_viewport>(vtable_slot(g_device, 41));
    return f ? f(d3d_device_, out) : -1;
}

long dev_GetRenderState(DWORD state, DWORD* out) {
    auto f = reinterpret_cast<fn_get_render_state>(vtable_slot(g_device, 51));
    return f ? f(d3d_device_, state, out) : -1;
}

long dev_SetRenderState(DWORD state, DWORD value) {
    auto f = reinterpret_cast<fn_set_render_state>(vtable_slot(g_device, 50));
    return f ? f(d3d_device_, state, value) : -1;
}

long dev_GetVertexShader(DWORD* out) {
    auto f = reinterpret_cast<fn_get_vertex_shader>(vtable_slot(g_device, 77));
    return f ? f(d3d_device_, out) : -1;
}

long dev_SetVertexShader(DWORD value) {
    auto f = reinterpret_cast<fn_set_vertex_shader>(vtable_slot(g_device, 76));
    return f ? f(d3d_device_, value) : -1;
}

long dev_GetTexture(DWORD stage, IDirect3DBaseTexture8** out) {
    auto f = reinterpret_cast<fn_get_texture>(vtable_slot(g_device, 60));
    return f ? f(d3d_device_, stage, reinterpret_cast<void**>(out)) : -1;
}

long dev_SetTexture(DWORD stage, void* texture) {
    auto f = reinterpret_cast<fn_set_texture>(vtable_slot(g_device, 61));
    return f ? f(d3d_device_, stage, texture) : -1;
}

long dev_DrawPrimitiveUP(DWORD type, unsigned count, void const* data, unsigned stride) {
    auto f = reinterpret_cast<fn_draw_up>(vtable_slot(g_device, 72));
    return f ? f(d3d_device_, type, count, data, stride) : -1;
}

D3DMATRIX cached_view_ {};
D3DMATRIX cached_projection_ {};
D3DMATRIX cached_view_projection_ {};
bool projection_matrices_valid_ = false;

DWORD saved_shader_ = 0;
DWORD saved_alpha_ = 0;
DWORD saved_src_ = 0;
DWORD saved_dest_ = 0;
DWORD saved_z_ = 0;
DWORD saved_lighting_ = 0;
DWORD saved_cull_ = 0;
IDirect3DBaseTexture8* saved_texture_ = nullptr;
bool draw_state_active_ = false;

DrawVertex batch_vertices_[max_batch_vertices_] {};
int batch_vertex_count_ = 0;

bool refresh_projection_matrices() {
    if (!d3d_device_) {
        return false;
    }

    if (dev_GetTransform(2, &cached_view_) < 0 || dev_GetTransform(3, &cached_projection_) < 0) {
        projection_matrices_valid_ = false;
        return false;
    }

    for (int row = 0; row < 4; ++row) {
        for (int column = 0; column < 4; ++column) {
            cached_view_projection_.m[row][column] =
                cached_view_.m[row][0] * cached_projection_.m[0][column]
                + cached_view_.m[row][1] * cached_projection_.m[1][column]
                + cached_view_.m[row][2] * cached_projection_.m[2][column]
                + cached_view_.m[row][3] * cached_projection_.m[3][column];
        }
    }

    projection_matrices_valid_ = true;
    return true;
}
float ring_cos_[ring_slices_ + 1] {};
float ring_sin_[ring_slices_ + 1] {};

void build_tables() {
    for (int i = 0; i <= ring_slices_; ++i) {
        float const angle = 6.28318530718f * static_cast<float>(i) / static_cast<float>(ring_slices_);
        ring_cos_[i] = std::cos(angle);
        ring_sin_[i] = std::sin(angle);
    }
}

void flush_batch();

DWORD scale_alpha(DWORD color, float scale) {
    const float alpha = static_cast<float>((color >> 24) & 0xFF) * scale;
    const DWORD clamped = static_cast<DWORD>(std::fmax(0.0f, std::fmin(255.0f, alpha)) + 0.5f);
    return (clamped << 24) | (color & 0x00FFFFFF);
}

float clamp01(float value) {
    return std::fmax(0.0f, std::fmin(1.0f, value));
}

float smoothstep(float t) {
    return t * t * (3.0f - 2.0f * t);
}

// The depth buffer is not usable at this point in the frame, so the far arc is
// faded by distance behind the mob instead. Normalising by radius keeps the
// effect identical on a hare and on a dragon.
float far_side_fade(float distance, float hub_distance, float radius) {
    if (radius <= 0.0f) {
        return 0.0f;
    }

    const float span = std::fmax(radius * kFadeSpan, 0.01f);
    return smoothstep(clamp01((distance - hub_distance) / span));
}


// FFXI world coordinates are x/y on the ground plane with z as height; D3D wants
// x/z on the ground with y up.
bool world_to_screen(const Position& point, const D3DVIEWPORT8& viewport,
    float& screen_x, float& screen_y, float& screen_rhw) {
    if (!projection_matrices_valid_) {
        return false;
    }

    const D3DMATRIX& vp = cached_view_projection_;
    const float d3d_x = point.east;
    const float d3d_y = point.height;
    const float d3d_z = point.north;

    const float clip_x = d3d_x * vp.m[0][0] + d3d_y * vp.m[1][0]
        + d3d_z * vp.m[2][0] + vp.m[3][0];
    const float clip_y = d3d_x * vp.m[0][1] + d3d_y * vp.m[1][1]
        + d3d_z * vp.m[2][1] + vp.m[3][1];
    const float clip_w = d3d_x * vp.m[0][3] + d3d_y * vp.m[1][3]
        + d3d_z * vp.m[2][3] + vp.m[3][3];

    if (std::fabs(clip_w) <= 0.0001f) {
        return false;
    }

    const float ndc_x = clip_x / clip_w;
    const float ndc_y = clip_y / clip_w;
    if (clip_w < 0.0f || ndc_x < -4.0f || ndc_x > 4.0f || ndc_y < -4.0f || ndc_y > 4.0f) {
        return false;
    }

    screen_x = static_cast<float>(viewport.X) + (ndc_x + 1.0f) * static_cast<float>(viewport.Width) * 0.5f;
    screen_y = static_cast<float>(viewport.Y) + (1.0f - ndc_y) * static_cast<float>(viewport.Height) * 0.5f;
    screen_rhw = 1.0f / clip_w;
    return true;
}

bool begin_draw_state() {
    if (draw_state_active_) {
        return true;
    }

    if (!d3d_device_) {
        return false;
    }

    saved_texture_ = nullptr;
    dev_GetVertexShader(&saved_shader_);
    dev_GetRenderState(D3DRS_ALPHABLENDENABLE, &saved_alpha_);
    dev_GetRenderState(D3DRS_SRCBLEND, &saved_src_);
    dev_GetRenderState(D3DRS_DESTBLEND, &saved_dest_);
    dev_GetRenderState(D3DRS_ZENABLE, &saved_z_);
    dev_GetRenderState(D3DRS_LIGHTING, &saved_lighting_);
    dev_GetRenderState(D3DRS_CULLMODE, &saved_cull_);
    dev_GetTexture(0, &saved_texture_);

    dev_SetTexture(0, nullptr);
    dev_SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
    dev_SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
    dev_SetRenderState(D3DRS_DESTBLEND, D3DBLEND_ONE);
    dev_SetRenderState(D3DRS_ZENABLE, FALSE);
    dev_SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
    dev_SetRenderState(D3DRS_LIGHTING, FALSE);
    dev_SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
    dev_SetRenderState(D3DRS_FOGENABLE, FALSE);
    dev_SetVertexShader(D3DFVF_XYZRHW | D3DFVF_DIFFUSE);

    draw_state_active_ = true;
    return true;
}

void end_draw_state() {
    if (!draw_state_active_ || !d3d_device_) {
        return;
    }

    dev_SetTexture(0, saved_texture_);
    if (saved_texture_) {
        saved_texture_->Release();
        saved_texture_ = nullptr;
    }
    dev_SetRenderState(D3DRS_ALPHABLENDENABLE, saved_alpha_);
    dev_SetRenderState(D3DRS_SRCBLEND, saved_src_);
    dev_SetRenderState(D3DRS_DESTBLEND, saved_dest_);
    dev_SetRenderState(D3DRS_ZENABLE, saved_z_);
    dev_SetRenderState(D3DRS_LIGHTING, saved_lighting_);
    dev_SetRenderState(D3DRS_CULLMODE, saved_cull_);
    dev_SetVertexShader(saved_shader_);
    draw_state_active_ = false;
}

void append_batch(const DrawVertex* vertices, int count) {
    if (count <= 0 || count > max_batch_vertices_) {
        return;
    }

    if (batch_vertex_count_ + count > max_batch_vertices_) {
        flush_batch();
    }

    std::memcpy(batch_vertices_ + batch_vertex_count_, vertices,
        static_cast<std::size_t>(count) * sizeof(DrawVertex));
    batch_vertex_count_ += count;
}

void flush_batch() {
    if (batch_vertex_count_ < 3 || !d3d_device_) {
        batch_vertex_count_ = 0;
        return;
    }

    dev_DrawPrimitiveUP(D3DPT_TRIANGLELIST,
        static_cast<UINT>(batch_vertex_count_ / 3), batch_vertices_, sizeof(DrawVertex));
    batch_vertex_count_ = 0;
}


void draw_ground_ring(const Position& centre, float radius,
    float band_width, const D3DVIEWPORT8& viewport, DWORD color) {
    if (radius <= 0.0f) {
        return;
    }

    const float inner_radius = std::fmax(radius - band_width * 0.5f, 0.01f);
    const float outer_radius = radius + band_width * 0.5f;

    const Position hub {centre.east, centre.north, centre.height - kGroundClearance};

    float hub_x = 0.0f;
    float hub_y = 0.0f;
    float hub_rhw = 1.0f;
    if (!world_to_screen(hub, viewport, hub_x, hub_y, hub_rhw) || hub_rhw <= 0.0f) {
        return;
    }

    const float hub_distance = 1.0f / hub_rhw;

    float inner_x[ring_slices_ + 1] {};
    float inner_y[ring_slices_ + 1] {};
    float outer_x[ring_slices_ + 1] {};
    float outer_y[ring_slices_ + 1] {};
    DWORD inner_color[ring_slices_ + 1] {};
    DWORD outer_color[ring_slices_ + 1] {};
    bool resolved[ring_slices_ + 1] {};

    for (int i = 0; i <= ring_slices_; ++i) {
        const float cos_a = ring_cos_[i];
        const float sin_a = ring_sin_[i];

        float inner_rhw = 1.0f;
        float outer_rhw = 1.0f;

        const Position near_point {hub.east + inner_radius * cos_a,
            hub.north + inner_radius * sin_a, hub.height};
        const Position far_point {hub.east + outer_radius * cos_a,
            hub.north + outer_radius * sin_a, hub.height};

        const bool inner_ok = world_to_screen(near_point, viewport, inner_x[i], inner_y[i], inner_rhw);
        const bool outer_ok = world_to_screen(far_point, viewport, outer_x[i], outer_y[i], outer_rhw);

        resolved[i] = inner_ok && outer_ok && inner_rhw > 0.0f && outer_rhw > 0.0f;
        if (!resolved[i]) {
            continue;
        }

        inner_color[i] = scale_alpha(color,
            1.0f - far_side_fade(1.0f / inner_rhw, hub_distance, radius));
        outer_color[i] = scale_alpha(color,
            1.0f - far_side_fade(1.0f / outer_rhw, hub_distance, radius));
    }

    DrawVertex quad[6] {};
    for (int i = 0; i < ring_slices_; ++i) {
        if (!resolved[i] || !resolved[i + 1]) {
            continue;
        }

        if (((inner_color[i] | outer_color[i] | inner_color[i + 1] | outer_color[i + 1])
            & 0xFF000000u) == 0) {
            continue;
        }

        quad[0] = {inner_x[i], inner_y[i], 0.0f, 1.0f, inner_color[i]};
        quad[1] = {outer_x[i], outer_y[i], 0.0f, 1.0f, outer_color[i]};
        quad[2] = {inner_x[i + 1], inner_y[i + 1], 0.0f, 1.0f, inner_color[i + 1]};
        quad[3] = {inner_x[i + 1], inner_y[i + 1], 0.0f, 1.0f, inner_color[i + 1]};
        quad[4] = {outer_x[i], outer_y[i], 0.0f, 1.0f, outer_color[i]};
        quad[5] = {outer_x[i + 1], outer_y[i + 1], 0.0f, 1.0f, outer_color[i + 1]};

        append_batch(quad, 6);
    }
}

std::uintptr_t g_entity_array = 0;
bool g_entity_array_resolved = false;

// mov edx,[esi+0xC] / mov eax,[edx+ebp] / mov eax,[eax*4+imm32] -- the trailing
// imm32 is the array base itself, not a pointer to it.
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
    if (!span_readable(match + sizeof(pattern), sizeof(base))) {
        return 0;
    }

    std::memcpy(&base, reinterpret_cast<void const*>(match + sizeof(pattern)), sizeof(base));
    if (!span_readable(base, sizeof(std::uintptr_t) * kMaxIndex)) {
        return 0;
    }

    g_entity_array = base;
    return g_entity_array;
}

bool live_position(DWORD index, Position& out) {
    std::uintptr_t const base = entity_array();
    if (base == 0 || index == 0 || index >= kMaxIndex) {
        return false;
    }

    std::uintptr_t const slot = base + static_cast<std::uintptr_t>(index) * sizeof(std::uintptr_t);
    if (!span_readable(slot, sizeof(std::uintptr_t))) {
        return false;
    }

    std::uintptr_t entity = 0;
    std::memcpy(&entity, reinterpret_cast<void const*>(slot), sizeof(entity));
    if (entity == 0) {
        return false;
    }

    float coords[3] {};
    bool have = false;

    if (span_readable(entity + kEntityDisplayPtr, sizeof(std::uintptr_t))) {
        std::uintptr_t display = 0;
        std::memcpy(&display, reinterpret_cast<void const*>(entity + kEntityDisplayPtr), sizeof(display));
        if (display != 0 && span_readable(display + kDisplayNameplateBase, sizeof(float) * 3)) {
            std::memcpy(coords, reinterpret_cast<void const*>(display + kDisplayNameplateBase),
                sizeof(coords));
            have = true;
        }
    }

    if (!have) {
        if (!span_readable(entity + kEntityDisplayPos, sizeof(float) * 3)) {
            return false;
        }

        std::memcpy(coords, reinterpret_cast<void const*>(entity + kEntityDisplayPos), sizeof(coords));
    }

    if (!std::isfinite(coords[0]) || !std::isfinite(coords[1]) || !std::isfinite(coords[2])
        || std::fabs(coords[0]) > 10000.0f || std::fabs(coords[1]) > 10000.0f
        || std::fabs(coords[2]) > 10000.0f) {
        return false;
    }

    out.east = coords[0];
    out.height = coords[1];
    out.north = coords[2];
    return true;
}

// Only reached when the entity array cannot supply a live position. Lua's
// coordinates are the server-side value (~2 Hz), so they are extrapolated by
// velocity between samples rather than used raw.
Position smooth_ring_position(DWORD index, Position const& target) {
    if (index == 0 || index >= kMaxIndex) {
        return target;
    }

    MotionState& state = g_motion[index];
    DWORD const now = GetTickCount();

    float dt = 0.016f;
    if (state.initialized && state.last_ms != 0 && now > state.last_ms) {
        dt = static_cast<float>(now - state.last_ms) * 0.001f;
        dt = std::fmin(std::fmax(dt, 0.001f), 0.05f);
    }

    if (!state.initialized) {
        state.pos = target;
        state.initialized = true;
        state.last_ms = now;
        return state.pos;
    }

    if (g_samples_fresh) {
        if (dt > 0.0f) {
            state.velocity.east = (target.east - state.pos.east) / dt;
            state.velocity.north = (target.north - state.pos.north) / dt;
            state.velocity.height = (target.height - state.pos.height) / dt;
        }

        state.pos = target;
        state.last_ms = now;
        return state.pos;
    }

    Position predicted = state.pos;
    predicted.east += state.velocity.east * dt;
    predicted.north += state.velocity.north * dt;
    predicted.height += state.velocity.height * dt;

    state.pos.east = predicted.east + (target.east - predicted.east) * (1.0f - kSmoothBlend);
    state.pos.north = predicted.north + (target.north - predicted.north) * (1.0f - kSmoothBlend);
    state.pos.height = predicted.height + (target.height - predicted.height) * (1.0f - kSmoothBlend);
    state.last_ms = now;
    return state.pos;
}

void draw_all_rings() {
    if (!d3d_device_) {
        return;
    }

    int const count = g_ring_count;
    if (count <= 0) {
        return;
    }

    D3DVIEWPORT8 viewport {};
    if (dev_GetViewport(&viewport) < 0 || viewport.Width == 0 || viewport.Height == 0) {
        return;
    }

    if (!refresh_projection_matrices()) {
        return;
    }

    if (!begin_draw_state()) {
        return;
    }

    batch_vertex_count_ = 0;

    for (int i = 0; i < count && i < kMaxRings; ++i) {
        Ring const& ring = g_rings[i];
        if (!ring.active || ring.radius <= 0.0f) {
            continue;
        }

        Position centre {};
        if (!live_position(ring.index, centre)) {
            centre = smooth_ring_position(ring.index, ring.centre);
        }

        draw_ground_ring(centre, ring.radius * 1.18f, ring.radius * 0.34f,
            viewport, scale_alpha(ring.color, 0.30f));
        draw_ground_ring(centre, ring.radius, ring.radius * 0.12f,
            viewport, scale_alpha(ring.color, 0.95f));
    }

    flush_batch();
    end_draw_state();
    g_samples_fresh = false;
    ++g_draws;
}

// FFXI does not keep the D3D8 device anywhere reachable by signature, but the
// renderer holds d3d8 resources, and every IDirect3DResource8 can hand back its
// creator via GetDevice at vtable slot 3. Scanning for a resource and asking it
// is far more reliable than trying to recognise the device by its vtable.
void acquire_device(std::uintptr_t renderer) {
    if (g_discovery_done || renderer == 0) {
        return;
    }

    g_discovery_done = true;

    std::uintptr_t d3d_base = 0;
    std::size_t d3d_size = 0;
    if (!module_range("d3d8.dll", d3d_base, d3d_size)) {
        return;
    }

    for (std::size_t offset = 0; offset + 4 <= 0x2000; offset += 4) {
        std::uintptr_t const slot = renderer + offset;
        if (!span_readable(slot, sizeof(std::uintptr_t))) {
            break;
        }

        std::uintptr_t resource = 0;
        std::memcpy(&resource, reinterpret_cast<void const*>(slot), sizeof(resource));
        if (resource == 0 || !span_readable(resource, sizeof(std::uintptr_t))) {
            continue;
        }

        std::uintptr_t vtable = 0;
        std::memcpy(&vtable, reinterpret_cast<void const*>(resource), sizeof(vtable));
        if (vtable < d3d_base || vtable >= d3d_base + d3d_size) {
            continue;
        }

        auto get_device = reinterpret_cast<fn_get_device>(vtable_slot(resource, 3));
        if (!get_device) {
            continue;
        }

        void* device = nullptr;
        if (get_device(reinterpret_cast<void*>(resource), &device) < 0 || !device) {
            continue;
        }

        std::uintptr_t const address = reinterpret_cast<std::uintptr_t>(device);
        if (!span_readable(address, sizeof(std::uintptr_t))) {
            continue;
        }

        std::uintptr_t device_vtable = 0;
        std::memcpy(&device_vtable, device, sizeof(device_vtable));
        if (device_vtable < d3d_base || device_vtable >= d3d_base + d3d_size) {
            continue;
        }

        g_device = address;
        d3d_device_ = device;

        auto release = reinterpret_cast<fn_release>(vtable_slot(address, 2));
        if (release) {
            release(device);
        }

        std::snprintf(g_status, sizeof(g_status), "running");
        return;
    }

    std::snprintf(g_status, sizeof(g_status), "device not found in renderer");
}

void __fastcall draw_scene_hook(void* renderer, void* unused) {
    g_trampoline(renderer, unused);

    g_renderer = reinterpret_cast<std::uintptr_t>(renderer);
    ++g_frames;

    acquire_device(g_renderer);
    draw_all_rings();
}

std::uintptr_t find_draw_scene() {
    static unsigned char const pattern[] = {
        0x56, 0x8B, 0xF1, 0x8B, 0x86, 0x50, 0x0D, 0x00, 0x00,
    };
    static char const mask[] = "xxxxxxxxx";
    return scan_module("FFXiMain.dll", pattern, mask, sizeof(pattern));
}

// draw_scene's prologue is exactly 9 bytes across three whole instructions, so a
// 5-byte jmp plus 4 nops replaces it without splitting one. Anything longer here
// would need a length disassembler.
bool install_hook() {
    if (g_hooked) {
        return true;
    }

    g_draw_scene = find_draw_scene();
    if (g_draw_scene == 0) {
        std::snprintf(g_status, sizeof(g_status), "draw_scene signature not found");
        return false;
    }

    void* trampoline = VirtualAlloc(nullptr, kPrologueBytes + 5, MEM_COMMIT | MEM_RESERVE,
        PAGE_EXECUTE_READWRITE);
    if (!trampoline) {
        std::snprintf(g_status, sizeof(g_status), "trampoline alloc failed");
        return false;
    }

    std::memcpy(g_original_bytes, reinterpret_cast<void const*>(g_draw_scene), kPrologueBytes);

    auto* bytes = static_cast<unsigned char*>(trampoline);
    std::memcpy(bytes, reinterpret_cast<void const*>(g_draw_scene), kPrologueBytes);
    bytes[kPrologueBytes] = 0xE9;
    std::int32_t const back = static_cast<std::int32_t>(
        (g_draw_scene + kPrologueBytes)
        - (reinterpret_cast<std::uintptr_t>(bytes) + kPrologueBytes + 5));
    std::memcpy(bytes + kPrologueBytes + 1, &back, sizeof(back));

    DWORD previous = 0;
    if (!VirtualProtect(reinterpret_cast<void*>(g_draw_scene), kPrologueBytes,
        PAGE_EXECUTE_READWRITE, &previous)) {
        std::snprintf(g_status, sizeof(g_status), "VirtualProtect failed");
        return false;
    }

    auto* target = reinterpret_cast<unsigned char*>(g_draw_scene);
    std::int32_t const jump = static_cast<std::int32_t>(
        reinterpret_cast<std::uintptr_t>(&draw_scene_hook) - (g_draw_scene + 5));
    target[0] = 0xE9;
    std::memcpy(target + 1, &jump, sizeof(jump));
    for (std::size_t i = 5; i < kPrologueBytes; ++i) {
        target[i] = 0x90;
    }

    VirtualProtect(reinterpret_cast<void*>(g_draw_scene), kPrologueBytes, previous, &previous);
    FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(g_draw_scene), kPrologueBytes);

    g_trampoline = reinterpret_cast<draw_scene_fn>(trampoline);
    g_hooked = true;
    std::snprintf(g_status, sizeof(g_status), "running");
    return true;
}

bool remove_hook() {
    if (!g_hooked) {
        return true;
    }

    g_ring_count = 0;
    g_hooked = false;

    DWORD previous = 0;
    if (!VirtualProtect(reinterpret_cast<void*>(g_draw_scene), kPrologueBytes,
        PAGE_EXECUTE_READWRITE, &previous)) {
        return false;
    }

    std::memcpy(reinterpret_cast<void*>(g_draw_scene), g_original_bytes, kPrologueBytes);
    VirtualProtect(reinterpret_cast<void*>(g_draw_scene), kPrologueBytes, previous, &previous);
    FlushInstructionCache(GetCurrentProcess(), reinterpret_cast<void*>(g_draw_scene), kPrologueBytes);

    // Give any thread currently inside the hook time to leave before the module
    // can be unloaded out from under it.
    Sleep(60);
    std::snprintf(g_status, sizeof(g_status), "unhooked");
    return true;
}

int __cdecl lua_start(lua_State* L) {
    install_hook();
    g_lua.pushstring(L, g_status);
    return 1;
}

int __cdecl lua_stop(lua_State* L) {
    remove_hook();
    g_lua.pushstring(L, g_status);
    return 1;
}

int __cdecl lua_status(lua_State* L) {
    char report[320] {};
    std::snprintf(report, sizeof(report),
        "hooked=%s frames=%lu draws=%lu device=%08lX entities=%08lX rings=%d | %s",
        g_hooked ? "yes" : "no", g_frames, g_draws,
        static_cast<unsigned long>(g_device),
        static_cast<unsigned long>(entity_array()), g_ring_count, g_status);
    g_lua.pushstring(L, report);
    return 1;
}

int __cdecl lua_clear(lua_State* L) {
    g_ring_count = 0;
    for (int i = 0; i < kMaxRings; ++i) {
        g_rings[i].active = false;
    }

    (void)L;
    return 0;
}

int __cdecl lua_add(lua_State* L) {
    if (g_lua.gettop(L) < 6) {
        return 0;
    }

    int const slot = g_ring_count;
    if (slot >= kMaxRings) {
        return 0;
    }

    Ring ring {};
    ring.index = static_cast<DWORD>(g_lua.tonumber(L, 1));
    ring.centre.east = static_cast<float>(g_lua.tonumber(L, 2));
    ring.centre.north = static_cast<float>(g_lua.tonumber(L, 3));
    ring.centre.height = static_cast<float>(g_lua.tonumber(L, 4));
    ring.radius = static_cast<float>(g_lua.tonumber(L, 5));
    ring.color = static_cast<DWORD>(g_lua.tonumber(L, 6));
    ring.active = true;
    g_samples_fresh = true;

    g_rings[slot] = ring;
    g_ring_count = slot + 1;
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

        g_lua.createtable = reinterpret_cast<fn_createtable>(
            reinterpret_cast<void*>(GetProcAddress(module, "lua_createtable")));
        g_lua.pushcclosure = reinterpret_cast<fn_pushcclosure>(
            reinterpret_cast<void*>(GetProcAddress(module, "lua_pushcclosure")));
        g_lua.setfield = reinterpret_cast<fn_setfield>(
            reinterpret_cast<void*>(GetProcAddress(module, "lua_setfield")));
        g_lua.pushvalue = reinterpret_cast<fn_pushvalue>(
            reinterpret_cast<void*>(GetProcAddress(module, "lua_pushvalue")));
        g_lua.pushstring = reinterpret_cast<fn_pushstring>(
            reinterpret_cast<void*>(GetProcAddress(module, "lua_pushstring")));
        g_lua.gettop = reinterpret_cast<fn_gettop>(
            reinterpret_cast<void*>(GetProcAddress(module, "lua_gettop")));
        g_lua.tonumber = reinterpret_cast<fn_tonumber>(
            reinterpret_cast<void*>(GetProcAddress(module, "lua_tonumber")));

        if (g_lua.ready()) {
            return true;
        }
    }

    return false;
}

}

extern "C" __declspec(dllexport) int __cdecl luaopen__TargetRing(lua_State* L) {
    if (!bind_lua()) {
        return 0;
    }

    build_tables();

    g_lua.createtable(L, 0, 5);

    g_lua.pushcclosure(L, lua_start, 0);
    g_lua.setfield(L, -2, "start");

    g_lua.pushcclosure(L, lua_stop, 0);
    g_lua.setfield(L, -2, "stop");

    g_lua.pushcclosure(L, lua_status, 0);
    g_lua.setfield(L, -2, "status");

    g_lua.pushcclosure(L, lua_clear, 0);
    g_lua.setfield(L, -2, "clear");

    g_lua.pushcclosure(L, lua_add, 0);
    g_lua.setfield(L, -2, "add");

    g_lua.pushvalue(L, -1);
    g_lua.setfield(L, kGlobalsIndex, "_TargetRing");
    return 1;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = instance;
    } else if (reason == DLL_PROCESS_DETACH) {
        remove_hook();
    }

    return TRUE;
}
