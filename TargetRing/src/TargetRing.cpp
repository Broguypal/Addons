#include "PluginInterface.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d8.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {
HMODULE g_module = nullptr;
}

class TargetRingPlugin final : public PluginBase {
public:
    const char* __stdcall GetPluginAuthor() override {
        return "Broguypal";
    }

    const char* __stdcall GetPluginName() override {
        return "targetring";
    }

    void __stdcall Load(PluginManager* manager) override {
        plugin_manager_ = manager;
        initialize_geometry_tables();
        initialize_paths_from_module();
        acquire_device();
        write_active_marker();
    }

    void __stdcall Unload() override {
        close_state_change_notification();
        DeleteFileA(marker_path_);
    }

    void __stdcall PreRender() override {
        prerender_matrices_valid_ = false;
        if (!d3d_device_) {
            acquire_device();
        }
        if (d3d_device_ && capture_projection_matrices_from_device()) {
            prerender_matrices_valid_ = true;
        }
    }

    void __stdcall PostRender() override {
        draw_ring_overlay();
    }

private:
    struct Position {
        float east = 0.0f;
        float north = 0.0f;
        float height = 0.0f;
    };

    static constexpr std::uintptr_t kContextSlot = 0x1c8400;
    static constexpr std::uintptr_t kTableSlot = 0x24;
    static constexpr std::uintptr_t kActorSlot = 0x0a0;
    static constexpr std::uintptr_t kRootX = 0x678;
    static constexpr std::uintptr_t kRootZ = 0x67C;
    static constexpr std::uintptr_t kRootY = 0x680;
    static constexpr std::size_t kEntryProbe = 0x0a4;
    static constexpr std::size_t kActorProbe = 0x700;
    static constexpr DWORD kMaxIndex = 0x900;
    static constexpr float kWorldLimit = 10000.0f;

    struct DrawVertex {
        float x;
        float y;
        float z;
        float rhw;
        DWORD color;
    };

    struct Entity {
        DWORD index = 0;
        bool is_npc = false;
        bool hostile = false;
        float model_size = 0.0f;
        float model_scale = 1.0f;
        float radius = 0.0f;
        bool has_radius = false;
        bool valid = false;
        bool has_pos = false;
        Position pos {};
    };

    static constexpr int ring_slices_ = 48;
    static constexpr float kPlayerFootprint = 0.64f;
    static constexpr float kFadeSpan = 0.55f;
    static constexpr float kGroundClearance = 0.05f;
    static constexpr float kOpacity = 0.85f;
    static constexpr unsigned kPulsePeriodMs = 1600u;
    static constexpr DWORD kHostileColour = 0xE6FF6A3C;
    static constexpr DWORD kFriendlyColour = 0xE64CC4FF;
    static constexpr int max_batch_vertices_ = 8192;

    void initialize_geometry_tables() {
        for (int i = 0; i <= ring_slices_; ++i) {
            const float angle = 6.28318530718f * static_cast<float>(i) / static_cast<float>(ring_slices_);
            ring_cos_[i] = std::cos(angle);
            ring_sin_[i] = std::sin(angle);
        }

    }

    void draw_ring_overlay() {
        if (menu_covers_screen()) {
            return;
        }

        read_state();

        if (!target_.valid && !subtarget_.valid) {
            return;
        }

        if (target_.valid && target_.has_pos) {
            Locator::discover_context_if_needed(target_.index, target_.pos);
        } else if (subtarget_.valid && subtarget_.has_pos) {
            Locator::discover_context_if_needed(subtarget_.index, subtarget_.pos);
        }

        if (!d3d_device_) {
            acquire_device();
        }

        if (!d3d_device_) {
            return;
        }

        IDirect3DSurface8* old_rt = nullptr;
        IDirect3DSurface8* old_ds = nullptr;
        IDirect3DSurface8* back = nullptr;
        const bool rebound = bind_back_buffer(old_rt, old_ds, back);

        D3DVIEWPORT8 viewport {};
        if (FAILED(d3d_device_->GetViewport(&viewport)) || viewport.Width == 0 || viewport.Height == 0) {
            restore_render_target(old_rt, old_ds, back, rebound);
            return;
        }

        if (!refresh_projection_matrices()) {
            restore_render_target(old_rt, old_ds, back, rebound);
            return;
        }

        std::uintptr_t mob_array = 0;
        const bool have_table = Locator::entity_table(mob_array);

        const float phase = static_cast<float>(GetTickCount() % kPulsePeriodMs)
            / static_cast<float>(kPulsePeriodMs);
        const float pulse = 0.72f + 0.28f * std::sin(phase * 6.28318530718f);

        if (!begin_draw_state()) {
            restore_render_target(old_rt, old_ds, back, rebound);
            return;
        }

        batch_vertex_count_ = 0;

        if (subtarget_.valid) {
            draw_entity_ring(mob_array, have_table, subtarget_, viewport,
                entity_colour(subtarget_), pulse);
        }

        if (target_.valid) {
            draw_entity_ring(mob_array, have_table, target_, viewport,
                entity_colour(target_), pulse);
        }

        flush_batch();
        end_draw_state();
        restore_render_target(old_rt, old_ds, back, rebound);

    }

    void draw_entity_ring(std::uintptr_t mob_array, bool have_table, const Entity& entity,
        const D3DVIEWPORT8& viewport, DWORD color, float pulse) {
        Position root {};
        bool have_root = false;

        if (have_table) {
            std::uintptr_t actor = 0;
            if (Locator::actor_for(mob_array, entity.index, actor)
                && Locator::ground_position(actor, root)) {
                have_root = true;
            }
        }
        if (!have_root && entity.has_pos) {
            root = entity.pos;
            have_root = true;
        }
        if (!have_root) {
            return;
        }

        const float radius = entity.has_radius ? entity.radius : entity_radius(entity);

        draw_ground_ring(root, radius * 1.18f, radius * 0.34f,
            viewport, scale_alpha(color, 0.30f * pulse * kOpacity));
        draw_ground_ring(root, radius, radius * 0.12f,
            viewport, scale_alpha(color, 0.95f * pulse * kOpacity));
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

    float far_side_fade(float distance, float hub_distance, float radius) const {
        if (radius <= 0.0f) {
            return 0.0f;
        }

        const float span = std::fmax(radius * kFadeSpan, 0.01f);
        return smoothstep(clamp01((distance - hub_distance) / span));
    }

    static DWORD entity_colour(const Entity& entity) {
        return entity.hostile ? kHostileColour : kFriendlyColour;
    }

    float entity_radius(const Entity& entity) const {
        static constexpr float kHumanoidExtent = 1.15f;
        static constexpr float kDefaultSize = 1.0f;

        float footprint = kPlayerFootprint;

        if (entity.is_npc) {
            const float scale = entity.model_scale > 0.0f ? entity.model_scale : 1.0f;
            const float size = entity.model_size > 0.0f ? entity.model_size : kDefaultSize;
            float extent = size * scale;

            if (extent > kHumanoidExtent) {
                extent = kHumanoidExtent + std::sqrt(extent - kHumanoidExtent) * 0.62f;
            }

            footprint = extent * 0.5f;
        }

        return std::fmax(std::fmin(footprint, 8.0f), 0.20f);
    }

    DWORD scale_alpha(DWORD color, float scale) const {
        const float alpha = static_cast<float>((color >> 24) & 0xFF) * scale;
        const DWORD clamped = static_cast<DWORD>(std::fmax(0.0f, std::fmin(255.0f, alpha)) + 0.5f);
        return (clamped << 24) | (color & 0x00FFFFFF);
    }

    static float clamp01(float value) {
        return std::fmax(0.0f, std::fmin(1.0f, value));
    }

    static float smoothstep(float t) {
        return t * t * (3.0f - 2.0f * t);
    }

    bool menu_covers_screen() {
        if (!menu_signature_resolved_) {
            menu_signature_ = MenuWatch::find_signature();
            menu_signature_resolved_ = true;
        }

        char name[24] {};
        if (!MenuWatch::active_menu(menu_signature_, name, sizeof(name))) {
            return false;
        }

        return MenuWatch::covers_screen(name);
    }

    void acquire_device() {
        d3d_device_ = plugin_manager_
            ? static_cast<IDirect3DDevice8*>(plugin_manager_->GetDirect3D8Device())
            : nullptr;
    }

    bool capture_projection_matrices_from_device() {
        if (!d3d_device_) {
            return false;
        }

        D3DMATRIX view {};
        D3DMATRIX projection {};
        if (FAILED(d3d_device_->GetTransform(D3DTS_VIEW, &view)) ||
            FAILED(d3d_device_->GetTransform(D3DTS_PROJECTION, &projection))) {
            return false;
        }

        const float view_trace = view.m[0][0] + view.m[1][1] + view.m[2][2];
        const float proj_m11 = projection.m[1][1];
        if (std::fabs(view_trace) < 0.0001f || std::fabs(proj_m11) < 0.0001f) {
            return false;
        }

        cached_view_ = view;
        cached_projection_ = projection;

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

    bool refresh_projection_matrices() {
        if (capture_projection_matrices_from_device()) {
            return true;
        }

        if (prerender_matrices_valid_ && projection_matrices_valid_) {
            return true;
        }

        projection_matrices_valid_ = false;
        return false;
    }

    bool world_to_screen(const Position& point, const D3DVIEWPORT8& viewport,
        float& screen_x, float& screen_y, float& screen_rhw) const {
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
        d3d_device_->GetVertexShader(&saved_shader_);
        d3d_device_->GetRenderState(D3DRS_ALPHABLENDENABLE, &saved_alpha_);
        d3d_device_->GetRenderState(D3DRS_SRCBLEND, &saved_src_);
        d3d_device_->GetRenderState(D3DRS_DESTBLEND, &saved_dest_);
        d3d_device_->GetRenderState(D3DRS_ZENABLE, &saved_z_);
        d3d_device_->GetRenderState(D3DRS_LIGHTING, &saved_lighting_);
        d3d_device_->GetRenderState(D3DRS_CULLMODE, &saved_cull_);
        d3d_device_->GetTexture(0, &saved_texture_);

        d3d_device_->SetTexture(0, nullptr);
        d3d_device_->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
        d3d_device_->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
        d3d_device_->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_ONE);
        d3d_device_->SetRenderState(D3DRS_ZENABLE, FALSE);
        d3d_device_->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
        d3d_device_->SetRenderState(D3DRS_LIGHTING, FALSE);
        d3d_device_->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
        d3d_device_->SetRenderState(D3DRS_FOGENABLE, FALSE);
        d3d_device_->SetVertexShader(D3DFVF_XYZRHW | D3DFVF_DIFFUSE);

        draw_state_active_ = true;
        return true;
    }

    void end_draw_state() {
        if (!draw_state_active_ || !d3d_device_) {
            return;
        }

        d3d_device_->SetTexture(0, saved_texture_);
        if (saved_texture_) {
            saved_texture_->Release();
            saved_texture_ = nullptr;
        }
        d3d_device_->SetRenderState(D3DRS_ALPHABLENDENABLE, saved_alpha_);
        d3d_device_->SetRenderState(D3DRS_SRCBLEND, saved_src_);
        d3d_device_->SetRenderState(D3DRS_DESTBLEND, saved_dest_);
        d3d_device_->SetRenderState(D3DRS_ZENABLE, saved_z_);
        d3d_device_->SetRenderState(D3DRS_LIGHTING, saved_lighting_);
        d3d_device_->SetRenderState(D3DRS_CULLMODE, saved_cull_);
        d3d_device_->SetVertexShader(saved_shader_);
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

        d3d_device_->DrawPrimitiveUP(D3DPT_TRIANGLELIST,
            static_cast<UINT>(batch_vertex_count_ / 3), batch_vertices_, sizeof(DrawVertex));
        batch_vertex_count_ = 0;
    }

    bool bind_back_buffer(IDirect3DSurface8*& old_rt, IDirect3DSurface8*& old_ds,
        IDirect3DSurface8*& back) {
        old_rt = nullptr;
        old_ds = nullptr;
        back = nullptr;
        if (!d3d_device_) {
            return false;
        }

        if (FAILED(d3d_device_->GetBackBuffer(0, D3DBACKBUFFER_TYPE_MONO, &back)) || !back) {
            return false;
        }

        d3d_device_->GetRenderTarget(&old_rt);
        d3d_device_->GetDepthStencilSurface(&old_ds);
        if (old_rt == back) {
            return true;
        }

        if (FAILED(d3d_device_->SetRenderTarget(back, old_ds))) {
            return false;
        }
        return true;
    }

    void restore_render_target(IDirect3DSurface8* old_rt, IDirect3DSurface8* old_ds,
        IDirect3DSurface8* back, bool rebound) {
        if (!d3d_device_) {
            return;
        }

        if (rebound && old_rt && old_rt != back) {
            d3d_device_->SetRenderTarget(old_rt, old_ds);
        }

        if (old_rt) {
            old_rt->Release();
        }
        if (old_ds) {
            old_ds->Release();
        }
        if (back) {
            back->Release();
        }
    }

    struct MenuWatch {
        static std::uintptr_t find_signature() {
            HMODULE game = GetModuleHandleA("FFXiMain.dll");
            if (!game) {
                return 0;
            }

            const std::uintptr_t base = reinterpret_cast<std::uintptr_t>(game);
            if (!Locator::span_readable(base, sizeof(IMAGE_DOS_HEADER))) {
                return 0;
            }

            const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
            if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
                return 0;
            }

            const std::uintptr_t nt_address = base + static_cast<std::uintptr_t>(dos->e_lfanew);
            if (!Locator::span_readable(nt_address, sizeof(IMAGE_NT_HEADERS32))) {
                return 0;
            }

            const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS32*>(nt_address);
            if (nt->Signature != IMAGE_NT_SIGNATURE) {
                return 0;
            }

            static const unsigned char pattern[] = {
                0x8B, 0x48, 0x0C, 0x85, 0xC9, 0x74, 0x00, 0x8B,
                0x51, 0x08, 0x85, 0xD2, 0x74, 0x00, 0x3B, 0x05,
            };
            static const char mask[] = "xxxxxx?xxxxxx?xx";
            const std::size_t length = sizeof(pattern);

            const auto* section = IMAGE_FIRST_SECTION(nt);
            for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section) {
                if (!Locator::span_readable(reinterpret_cast<std::uintptr_t>(section), sizeof(IMAGE_SECTION_HEADER))) {
                    return 0;
                }

                if ((section->Characteristics & IMAGE_SCN_MEM_EXECUTE) == 0) {
                    continue;
                }

                const std::uintptr_t start = base + section->VirtualAddress;
                const std::size_t span = section->Misc.VirtualSize;
                if (span <= length || !Locator::span_readable(start, span)) {
                    continue;
                }

                const auto* bytes = reinterpret_cast<const unsigned char*>(start);
                for (std::size_t offset = 0; offset + length <= span; ++offset) {
                    bool hit = true;
                    for (std::size_t j = 0; j < length; ++j) {
                        if (mask[j] != '?' && bytes[offset + j] != pattern[j]) {
                            hit = false;
                            break;
                        }
                    }

                    if (hit) {
                        return start + offset + length;
                    }
                }
            }

            return 0;
        }

        static bool active_menu(std::uintptr_t signature, char* out, std::size_t size) {
            if (signature == 0 || size < 17) {
                return false;
            }

            out[0] = '\0';

            std::uint32_t holder = 0;
            std::uint32_t top = 0;
            std::uint32_t header = 0;
            if (!Locator::fetch(signature, holder) || holder == 0 ||
                !Locator::fetch(static_cast<std::uintptr_t>(holder), top) || top == 0 ||
                !Locator::fetch(static_cast<std::uintptr_t>(top) + 4, header) || header == 0) {
                return false;
            }

            const std::uintptr_t text = static_cast<std::uintptr_t>(header) + 0x46;
            if (!Locator::span_readable(text, 16)) {
                return false;
            }

            std::memcpy(out, reinterpret_cast<const void*>(text), 16);
            out[16] = '\0';
            return true;
        }

        static bool covers_screen(const char* name) {
            if (!name || std::strncmp(name, "menu", 4) != 0) {
                return false;
            }

            const char* cursor = name + 4;
            while (*cursor == ' ') {
                ++cursor;
            }

            return std::strncmp(cursor, "map", 3) == 0
                || std::strncmp(cursor, "scanlist", 8) == 0
                || std::strncmp(cursor, "cnqframe", 8) == 0;
        }
    };

    struct Locator {
        static bool page_readable(DWORD protect) {
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

        static bool span_readable(std::uintptr_t address, std::size_t size) {
            if (address == 0 || size == 0) {
                return false;
            }

            MEMORY_BASIC_INFORMATION region {};
            if (!VirtualQuery(reinterpret_cast<const void*>(address), &region, sizeof(region))) {
                return false;
            }

            if (region.State != MEM_COMMIT || !page_readable(region.Protect)) {
                return false;
            }

            const std::uintptr_t low = reinterpret_cast<std::uintptr_t>(region.BaseAddress);
            return address >= low && address + size <= low + region.RegionSize;
        }

        template<typename T>
        static bool fetch(std::uintptr_t address, T& out) {
            if (!span_readable(address, sizeof(T))) {
                return false;
            }

            SIZE_T copied = 0;
            return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<const void*>(address),
                &out, sizeof(T), &copied) && copied == sizeof(T);
        }

        static bool follow(std::uintptr_t address, std::uintptr_t& out, std::size_t required) {
            return fetch(address, out) && span_readable(out, required);
        }

        static bool plausible(float value, float limit) {
            return std::isfinite(value) && std::fabs(value) <= limit;
        }

        static std::uintptr_t& context_offset() {
            static std::uintptr_t offset = kContextSlot;
            return offset;
        }

        static bool& discovery_finished() {
            static bool done = false;
            return done;
        }

        static bool entity_table_at(std::uintptr_t core_base, std::uintptr_t offset,
            std::uintptr_t& table) {
            table = 0;
            std::uintptr_t context = 0;
            if (!fetch(core_base + offset, context) || context == 0) {
                return false;
            }

            if (!follow(context + kTableSlot, table, sizeof(std::uintptr_t) * kMaxIndex)) {
                table = 0;
                return false;
            }

            return true;
        }

        static bool validate_context(std::uintptr_t core_base, std::uintptr_t offset,
            DWORD index, const Position& hint) {
            std::uintptr_t table = 0;
            if (!entity_table_at(core_base, offset, table)) {
                return false;
            }

            std::uintptr_t actor = 0;
            Position root {};
            if (!actor_for(table, index, actor) || !ground_position(actor, root)) {
                return false;
            }

            const float dx = root.east - hint.east;
            const float dy = root.north - hint.north;
            const float dz = root.height - hint.height;
            return (dx * dx + dy * dy + dz * dz) < 64.0f; // within 8 yalms of Lua hint
        }

        static void discover_context_if_needed(DWORD index, const Position& hint) {
            if (discovery_finished() || index == 0) {
                return;
            }

            HMODULE core = GetModuleHandleA("LuaCore.dll");
            if (!core) {
                discovery_finished() = true;
                return;
            }

            const std::uintptr_t base = reinterpret_cast<std::uintptr_t>(core);
            if (validate_context(base, context_offset(), index, hint)) {
                discovery_finished() = true;
                return;
            }

            for (std::intptr_t delta = 4; delta <= 0x30000; delta += 4) {
                const std::uintptr_t up = kContextSlot + static_cast<std::uintptr_t>(delta);
                const std::uintptr_t down = kContextSlot - static_cast<std::uintptr_t>(delta);
                if (validate_context(base, up, index, hint)) {
                    context_offset() = up;
                    discovery_finished() = true;
                    return;
                }
                if (delta < static_cast<std::intptr_t>(kContextSlot)
                    && validate_context(base, down, index, hint)) {
                    context_offset() = down;
                    discovery_finished() = true;
                    return;
                }
            }

            discovery_finished() = true;
        }

        static bool entity_table(std::uintptr_t& table) {
            table = 0;

            HMODULE core = GetModuleHandleA("LuaCore.dll");
            if (!core) {
                return false;
            }

            return entity_table_at(reinterpret_cast<std::uintptr_t>(core),
                context_offset(), table);
        }

        static bool actor_for(std::uintptr_t table, DWORD index, std::uintptr_t& actor) {
            actor = 0;
            if (table == 0 || index == 0 || index >= kMaxIndex) {
                return false;
            }

            std::uintptr_t entry = 0;
            if (!follow(table + static_cast<std::uintptr_t>(index) * sizeof(std::uintptr_t),
                    entry, kEntryProbe)) {
                return false;
            }

            if (!follow(entry + kActorSlot, actor, kActorProbe)) {
                actor = 0;
                return false;
            }

            return true;
        }

        static bool ground_position(std::uintptr_t actor, Position& out) {
            float east = 0.0f;
            float height = 0.0f;
            float north = 0.0f;

            if (!fetch(actor + kRootX, east) ||
                !fetch(actor + kRootZ, height) ||
                !fetch(actor + kRootY, north)) {
                return false;
            }

            if (!plausible(east, kWorldLimit) || !plausible(north, kWorldLimit)
                || !plausible(height, kWorldLimit)) {
                return false;
            }

            out = {east, north, height};
            return true;
        }

    };

    void read_state() {
        if (!state_file_may_have_changed()) {
            return;
        }

        WIN32_FILE_ATTRIBUTE_DATA attributes {};
        if (!GetFileAttributesExA(state_path_, GetFileExInfoStandard, &attributes)) {
            return;
        }

        ULARGE_INTEGER write_time {};
        write_time.LowPart = attributes.ftLastWriteTime.dwLowDateTime;
        write_time.HighPart = attributes.ftLastWriteTime.dwHighDateTime;
        const unsigned long long file_size =
            (static_cast<unsigned long long>(attributes.nFileSizeHigh) << 32) | attributes.nFileSizeLow;

        if (state_cache_valid_ && cached_write_time_ == write_time.QuadPart && cached_file_size_ == file_size) {
            return;
        }

        FILE* file = std::fopen(state_path_, "rb");
        if (!file) {
            return;
        }

        char buffer[4096] {};
        const std::size_t read = std::fread(buffer, 1, sizeof(buffer) - 1, file);
        std::fclose(file);
        buffer[read] = '\0';

        std::size_t content_end = read;
        while (content_end > 0 && (buffer[content_end - 1] == ' ' || buffer[content_end - 1] == '\t'
            || buffer[content_end - 1] == '\r' || buffer[content_end - 1] == '\n')) {
            --content_end;
        }

        if (content_end == 0 || buffer[0] != '{' || buffer[content_end - 1] != '}') {
            return;
        }

        target_ = parse_entity(buffer, "\"target\"");
        subtarget_ = parse_entity(buffer, "\"subtarget\"");

        cached_write_time_ = write_time.QuadPart;
        cached_file_size_ = file_size;
        state_cache_valid_ = true;
    }

    Entity parse_entity(const char* buffer, const char* key) const {
        Entity entity {};

        const char* key_pos = std::strstr(buffer, key);
        if (!key_pos) {
            return entity;
        }

        const char* colon = std::strchr(key_pos, ':');
        if (!colon) {
            return entity;
        }

        const char* cursor = colon + 1;
        while (*cursor == ' ') {
            ++cursor;
        }

        if (*cursor != '{') {
            return entity;
        }

        const char* object_end = std::strchr(cursor, '}');
        if (!object_end) {
            return entity;
        }

        char object[512] {};
        const std::size_t length = std::min(static_cast<std::size_t>(object_end - cursor + 1), sizeof(object) - 1);
        std::memcpy(object, cursor, length);
        object[length] = '\0';

        entity.index = parse_json_uint(object, "\"index\"");
        entity.is_npc = parse_json_bool(object, "\"npc\"");
        entity.hostile = parse_json_bool(object, "\"hostile\"");
        entity.model_size = parse_json_float(object, "\"model_size\"");
        entity.model_scale = parse_json_float(object, "\"model_scale\"");
        entity.radius = parse_json_float(object, "\"radius\"");
        entity.has_radius = entity.radius > 0.05f;
        entity.valid = entity.index != 0 && entity.index < 0x900;
        if (std::strstr(object, "\"x\"") && std::strstr(object, "\"y\"")
            && std::strstr(object, "\"z\"")) {
            entity.pos.east = parse_json_float(object, "\"x\"");
            entity.pos.north = parse_json_float(object, "\"y\"");
            entity.pos.height = parse_json_float(object, "\"z\"");
            entity.has_pos = Locator::plausible(entity.pos.east, kWorldLimit)
                && Locator::plausible(entity.pos.north, kWorldLimit)
                && Locator::plausible(entity.pos.height, kWorldLimit);
        }
        return entity;
    }

    bool state_file_may_have_changed() {
        if (!state_cache_valid_ || state_change_notification_ == INVALID_HANDLE_VALUE) {
            return true;
        }

        const DWORD wait_result = WaitForSingleObject(state_change_notification_, 0);
        if (wait_result == WAIT_TIMEOUT) {
            return false;
        }

        if (wait_result == WAIT_OBJECT_0) {
            if (!FindNextChangeNotification(state_change_notification_)) {
                close_state_change_notification();
            }
            return true;
        }

        close_state_change_notification();
        return true;
    }

    float parse_json_float(const char* start, const char* key) const {
        const char* key_pos = std::strstr(start, key);
        if (!key_pos) {
            return 0.0f;
        }

        const char* colon = std::strchr(key_pos, ':');
        return colon ? static_cast<float>(std::strtod(colon + 1, nullptr)) : 0.0f;
    }

    DWORD parse_json_uint(const char* start, const char* key) const {
        const char* key_pos = std::strstr(start, key);
        if (!key_pos) {
            return 0;
        }

        const char* colon = std::strchr(key_pos, ':');
        return colon ? std::strtoul(colon + 1, nullptr, 10) : 0;
    }

    bool parse_json_bool(const char* start, const char* key) const {
        const char* key_pos = std::strstr(start, key);
        if (!key_pos) {
            return false;
        }

        const char* colon = std::strchr(key_pos, ':');
        if (!colon) {
            return false;
        }

        while (*(++colon) == ' ') {
        }

        return std::strncmp(colon, "true", 4) == 0;
    }

    void initialize_paths_from_module() {
        char module_path[MAX_PATH] {};
        if (!g_module || !GetModuleFileNameA(g_module, module_path, sizeof(module_path))) {
            return;
        }

        char* slash = std::strrchr(module_path, '\\');
        if (!slash) {
            return;
        }

        *slash = '\0';
        char settings_root[MAX_PATH] {};
        std::snprintf(settings_root, sizeof(settings_root), "%s\\settings", module_path);
        CreateDirectoryA(settings_root, nullptr);
        std::snprintf(settings_root, sizeof(settings_root), "%s\\settings\\TargetRing", module_path);
        CreateDirectoryA(settings_root, nullptr);
        std::snprintf(state_path_, sizeof(state_path_), "%s\\settings\\TargetRing\\target.json", module_path);
        std::snprintf(marker_path_, sizeof(marker_path_), "%s\\settings\\TargetRing\\plugin.active", module_path);
        state_change_notification_ = FindFirstChangeNotificationA(
            settings_root,
            FALSE,
            FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_SIZE | FILE_NOTIFY_CHANGE_LAST_WRITE);
    }

    void write_active_marker() {
        if (marker_path_[0] == '\0') {
            return;
        }

        FILE* file = std::fopen(marker_path_, "wb");
        if (file) {
            std::fputs("running\n", file);
            std::fclose(file);
        }
    }

    void close_state_change_notification() {
        if (state_change_notification_ != INVALID_HANDLE_VALUE) {
            FindCloseChangeNotification(state_change_notification_);
            state_change_notification_ = INVALID_HANDLE_VALUE;
        }
    }

    char state_path_[1024] {};
    char marker_path_[1024] {};
    std::uintptr_t menu_signature_ = 0;
    bool menu_signature_resolved_ = false;
    HANDLE state_change_notification_ = INVALID_HANDLE_VALUE;

    IDirect3DDevice8* d3d_device_ = nullptr;
    D3DMATRIX cached_view_ {};
    D3DMATRIX cached_projection_ {};
    D3DMATRIX cached_view_projection_ {};
    bool projection_matrices_valid_ = false;
    bool prerender_matrices_valid_ = false;

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

    Entity target_ {};
    Entity subtarget_ {};
    unsigned long long cached_write_time_ = 0;
    unsigned long long cached_file_size_ = 0;
    bool state_cache_valid_ = false;

    float ring_cos_[ring_slices_ + 1] {};
    float ring_sin_[ring_slices_ + 1] {};
};

std::uint32_t GetInterfaceVersion() {
    return WINDOWER_INTERFACE_VERSION;
}

PluginBase* CreateInstance() {
    return new TargetRingPlugin();
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_module = instance;
    }

    return TRUE;
}
