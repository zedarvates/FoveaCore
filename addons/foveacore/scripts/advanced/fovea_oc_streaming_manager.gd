class_name FoveaOCStreamingManager
extends FoveaStreamingManager

## FoveaEngine — Out-of-Core Streaming (items 218-235)
## LRU chunked streaming with Morton-order chunks.

@export var chunk_size: int = 65536  # splats per chunk
@export var memory_budget_mb: int = 2048
@export var fade_in_time: float = 0.3

var _lru_queue: Array[String] = []
var _chunk_table: Dictionary = {}  # chunk_id → {offset, size, aabb, state}

enum ChunkState { RESIDENT, LOADING, EVICTED }

func load_chunk(chunk_id: String) -> void:
	if _chunk_table.get(chunk_id, {}).get("state") == ChunkState.RESIDENT:
		_lru_queue.erase(chunk_id)
		_lru_queue.push_back(chunk_id)
		return
	_chunk_table[chunk_id] = {"state": ChunkState.LOADING, "fade": 0.0}
	# Async read from disk → GPU upload
	_start_async_load(chunk_id)
	_lru_queue.push_back(chunk_id)

func _enforce_budget() -> void:
	while _lru_queue.size() * chunk_size > memory_budget_mb * 1024 * 1024 / 32:
		var oldest = _lru_queue.pop_front()
		if oldest: _evict_chunk(oldest)

func _evict_chunk(chunk_id: String) -> void:
	_chunk_table[chunk_id] = {"state": ChunkState.EVICTED}
