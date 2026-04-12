# performance_benchmark.gd
# Godot 4.x script for benchmarking Proxy Reconstruction performance
# Measures FPS, frame time, and other metrics to validate +40-60% FPS gain target

extends Node

# Configuration
@export var test_duration: float = 30.0  # seconds per test
@export var test_distances: Array = [1.0, 3.0, 6.0, 12.0]  # meters from camera
@export var foveation_levels: Array = [0, 1, 2, 3]  # 0=None, 1=Low, 2=Med, 3=High
@export var save_results: bool = true
@export var results_file: String = "user://proxy_performance_results.csv"

# References
var _proxy_renderer: ProxyFaceRenderer = null
var _fovea_proxy_manager: FoveaProxyManager = null
var _xr_initializer: FoveaXRInitializer = null
var _camera: XRCamera3D = null
var _camera_relative: Camera3D = null

# Metrics tracking
var _frame_times: Array = []
var _fps_samples: Array = []
var _test_results: Array = []
var _current_test_index: int = 0
var _is_testing: bool = false
var _test_start_time: float = 0.0
var _frames_rendered: int = 0

func _ready() -> void:
    # Find required nodes
    _find_nodes()
    
    # Auto-start testing if in editor (for quick validation)
    if Engine.is_editor_hint():
        set_process(true)
        _start_performance_test()
    else:
        # Wait for user to start test via signal or method call
        set_process(false)

func _find_nodes() -> void:
    var parent = get_parent()
    if parent == null:
        push_warning("PerformanceBenchmark: No parent node found")
        return
        
    _proxy_renderer = parent.get_node_or_null("ProxyFaceRenderer") as ProxyFaceRenderer
    _fovea_proxy_manager = parent.get_node_or_null("FoveaProxyManager") as FoveaProxyManager
    _xr_initializer = parent.get_node_or_null("FoveaXRInitializer") as FoveaXRInitializer
    _camera = parent.get_node_or_null("XRCamera3D") as XRCamera3D
    _camera_relative = parent.get_node_or_null("Camera3D") as Camera3D
    
    if _proxy_renderer == null:
        push_warning("PerformanceBenchmark: ProxyFaceRenderer not found")
    if _fovea_proxy_manager == null:
        push_warning("PerformanceBenchmark: FoveaProxyManager not found")
    if _xr_initializer == null:
        push_warning("PerformanceBenchmark: FoveaXRInitializer not found")
    if _camera == null and _camera_relative == null:
        push_warning("PerformanceBenchmark: No Camera3D (XR or standard) found")

func _start_performance_test() -> void:
    if _is_testing:
        push_warning("PerformanceBenchmark: Test already in progress")
        return
        
    if not _validate_dependencies():
        push_error("PerformanceBenchmark: Missing dependencies, cannot start test")
        return
        
    _is_testing = true
    _current_test_index = 0
    _test_results.clear()
    _frame_times.clear()
    _fps_samples.clear()
    _frames_rendered = 0
    
    print("PerformanceBenchmark: Starting proxy reconstruction performance test")
    _run_next_test()

func _validate_dependencies() -> bool:
    return _proxy_renderer != null and _fovea_proxy_manager != null and \
           _xr_initializer != null and (_camera != null or _camera_relative != null)

func _run_next_test() -> void:
    if _current_test_index >= test_distances.size() * foveation_levels.size():
        _complete_test_suite()
        return
        
    # Calculate current test parameters
    var distance_index = _current_test_index % test_distances.size()
    var fov_index = _current_test_index / test_distances.size()
    
    var test_distance = test_distances[distance_index]
    var fov_level = foveation_levels[fov_index]
    
    print("PerformanceBenchmark: Starting test %d - Distance: %.1fm, Foveation: %d" % 
              [_current_test_index + 1, test_distance, fov_level])
              
    # Setup test conditions
    _setup_test_conditions(test_distance, fov_level)
    
    # Reset metrics
    _frame_times.clear()
    _fps_samples.clear()
    _frames_rendered = 0
    _test_start_time = Time.get_ticks_msec()
    
    # Enable processing to collect metrics
    set_process(true)

func _setup_test_conditions(distance: float, fov_level: int) -> void:
    # Position the proxy renderer at test distance
    if _proxy_renderer:
        var cam = _camera if _camera != null else _camera_relative
        if cam:
            var camera_pos = cam.global_transform.origin
            var forward = -cam.global_transform.basis.z
            var target_pos = camera_pos + forward * distance
            _proxy_renderer.global_transform.origin = target_pos
        
    # Set foveation level
    if _xr_initializer:
        _xr_initializer.foveation_level = fov_level
        
    # Update proxy manager to reflect new conditions
    if _fovea_proxy_manager:
        _fovea_proxy_manager._update_density_based_on_foveation(0.0)  # Force immediate update

func _process(delta: float) -> void:
    if not _is_testing:
        return
        
    # Collect frame metrics
    var frame_start = Time.get_ticks_usec()
    await Engine.get_main_loop().process_frame
    var frame_end = Time.get_ticks_usec()
    
    var frame_time_ms = (frame_end - frame_start) / 1000.0
    var fps = 1000.0 / frame_time_ms if frame_time_ms > 0 else 0.0
    
    _frame_times.append(frame_time_ms)
    _fps_samples.append(fps)
    _frames_rendered += 1
    
    # Check if test duration has elapsed
    var elapsed_time = (Time.get_ticks_msec() - _test_start_time) / 1000.0
    if elapsed_time >= test_duration:
        _complete_current_test()

func _complete_current_test() -> void:
    set_process(false)  # Stop collecting metrics
    
    # Calculate average metrics for this test
    var sum_frame_times = 0.0
    for t in _frame_times: sum_frame_times += t
    var avg_frame_time = sum_frame_times / _frame_times.size() if _frame_times.size() > 0 else 0.0
    
    var sum_fps = 0.0
    for f in _fps_samples: sum_fps += f
    var avg_fps = sum_fps / _fps_samples.size() if _fps_samples.size() > 0 else 0.0
    
    var min_fps = 0.0
    if _fps_samples.size() > 0:
        min_fps = _fps_samples[0]
        for f in _fps_samples: if f < min_fps: min_fps = f
        
    var max_fps = 0.0
    if _fps_samples.size() > 0:
        max_fps = _fps_samples[0]
        for f in _fps_samples: if f > max_fps: max_fps = f
    
    # Get current test parameters
    var distance_index = (_current_test_index % test_distances.size())
    var fov_index = (_current_test_index / test_distances.size())
    var test_distance = test_distances[distance_index]
    var fov_level = foveation_levels[fov_index]
    
    # Store results
    var result = {
        "test_index": _current_test_index,
        "distance_m": test_distance,
        "foveation_level": fov_level,
        "avg_fps": avg_fps,
        "min_fps": min_fps,
        "max_fps": max_fps,
        "avg_frame_time_ms": avg_frame_time,
        "frames_rendered": _frames_rendered,
        "test_duration_s": test_duration
    }
    _test_results.append(result)
    
    print("PerformanceBenchmark: Test %d complete - Avg FPS: %.1f, Min: %.1f, Max: %.1f" % 
              [_current_test_index + 1, avg_fps, min_fps, max_fps])
              
    # Move to next test
    _current_test_index += 1
    _run_next_test()

func _complete_test_suite() -> void:
    _is_testing = false
    print("PerformanceBenchmark: All tests completed!")
    
    # Calculate overall results and improvements
    _analyze_results()
    
    # Save results if requested
    if save_results:
        _save_results_to_file()
        
    # Notify completion via signal
    performance_test_complete.emit(_test_results)

func _analyze_results() -> void:
    if _test_results.size() == 0:
        push_warning("PerformanceBenchmark: No results to analyze")
        return
        
    print("PerformanceBenchmark: === PERFORMANCE ANALYSIS ===")
    
    # Find baseline (closest to 0m distance, any foveation level)
    var baseline_fps: float = 0.0
    var baseline_index: int = -1
    for i in _test_results.size():
        var result = _test_results[i]
        if result.distance_m <= 2.0:  # Within 2m = baseline
            if baseline_index == -1 or result.distance_m < _test_results[baseline_index].distance_m:
                baseline_index = i
                baseline_fps = result.avg_fps
                
    if baseline_index == -1:
        push_warning("PerformanceBenchmark: No baseline test found (distance <= 2m)")
        return
        
    print("PerformanceBenchmark: Baseline FPS (%.1fm): %.1f" % 
              [_test_results[baseline_index].distance_m, baseline_fps])
              
    # Analyze each test vs baseline
    for result in _test_results:
        var improvement_pct: float = 0.0
        if baseline_fps > 0:
            improvement_pct = ((result.avg_fps - baseline_fps) / baseline_fps) * 100.0
            
        var status: String
        if improvement_pct >= 40.0:
            status = "EXCELLENT (≥40%)"
        elif improvement_pct >= 20.0:
            status = "GOOD (≥20%)"
        elif improvement_pct >= 0.0:
            status = "ACCEPTABLE (≥0%)"
        else:
            status = "REGRESSION (<0%)"
            
        print("PerformanceBenchmark: %.1fm, Fov%d - FPS: %.1f (Δ%.1f%%) - %s" % 
                  [result.distance_m, result.foveation_level, result.avg_fps, improvement_pct, status])

func _save_results_to_file() -> void:
    var file = FileAccess.open(results_file, FileAccess.WRITE)
    if file == null:
        push_error("PerformanceBenchmark: Cannot open results file for writing: %s" % results_file)
        return
        
    # Write CSV header
    file.store_line("TestIndex,Distance_m,FoveationLevel,AvgFPS,MinFPS,MaxFPS,AvgFrameTime_ms,FramesRendered,TestDuration_s")
    
    # Write data rows
    for result in _test_results:
        var line = "%d,%.1f,%d,%.1f,%.1f,%.1f,%.1f,%d,%.1f" % [
            result.test_index,
            result.distance_m,
            result.foveation_level,
            result.avg_fps,
            result.min_fps,
            result.max_fps,
            result.avg_frame_time_ms,
            result.frames_rendered,
            result.test_duration_s
        ]
        file.store_line(line)
        
    file.close()
    print("PerformanceBenchmark: Results saved to: %s" % results_file)

# Signal declaration
signal performance_test_complete(results: Array)

# Public API
func start_benchmark() -> void:
    _start_performance_test()

func is_testing() -> bool:
    return _is_testing

func get_results() -> Array:
    return _test_results.duplicate()  # Return copy to prevent external modification