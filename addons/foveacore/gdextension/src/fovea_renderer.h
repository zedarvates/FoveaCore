#ifndef FOVEA_RENDERER_H
#define FOVEA_RENDERER_H

#include <godot_cpp/classes/node.hpp>

namespace godot {

class FoveaRenderer : public Node {
    GDCLASS(FoveaRenderer, Node)

private:
    bool _vr_enabled = false;
    bool _foveated_enabled = true;
    float _splat_density = 1.0f;

protected:
    static void _bind_methods();

public:
    FoveaRenderer();
    ~FoveaRenderer();
    
    // Getters
    bool is_vr_enabled() const { return _vr_enabled; }
    bool is_foveated_enabled() const { return _foveated_enabled; }
    float get_splat_density() const { return _splat_density; }
    
    // Setters
    void set_vr_enabled(bool enabled) { _vr_enabled = enabled; }
    void set_foveated_enabled(bool enabled) { _foveated_enabled = enabled; }
    void set_splat_density(float density) { _splat_density = CLAMP(density, 0.1f, 5.0f); }
};

} // namespace godot

#endif // FOVEA_RENDERER_H
