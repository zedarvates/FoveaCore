#include "register_types.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include "fovea_renderer.h"

void initialize_foveacore_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    // ✅ VRAI FIX pour Godot 4.3+ : évite l'erreur d'enregistrement double
    // Godot appelle _register_extension_class_internal AUTOMATIQUEMENT avant notre callback
    // Donc on vérifie si la classe existe déjà AVANT de l'enregistrer
    if (!ClassDB::class_exists("FoveaRenderer")) {
        ClassDB::register_class<FoveaRenderer>();
    }
}

void uninitialize_foveacore_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    // Ne pas désenregistrer la classe : Godot s'occupe déjà de ça
    // Le désenregistrement manuel est la cause principale de l'erreur d'enregistrement double
}

extern "C" {

GDExtensionBool GDE_EXPORT foveacore_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize_foveacore_module);
    init_obj.register_terminator(uninitialize_foveacore_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}

}
