extends SceneTree

# Unit test for FoveaLiveLinkReceiver (UDP Mocap Receiver)

const ReceiverClass := preload("res://addons/foveacore/scripts/advanced/fovea_live_link_receiver.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n======================================================================")
	print("FoveaEngine - Live Link Mocap Receiver Unit Tests")
	print("======================================================================")
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	await _test_packet_reception_and_decoding()
	_finish()

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)

func _test_packet_reception_and_decoding() -> void:
	print("\n--- Test 1: UDP Ingestion & Decoding ---")
	
	var receiver := ReceiverClass.new()
	receiver.port = 5006
	receiver.active = true
	root.add_child(receiver)
	
	# Laisser le temps au serveur UDP de bind
	await create_timer(0.1).timeout
	_assert("Receiver server is bound", receiver._udp.is_bound())
	
	if not receiver._udp.is_bound():
		receiver.queue_free()
		return
		
	# Simuler l'envoi d'un paquet UDP en local
	var sender := PacketPeerUDP.new()
	var err := sender.connect_to_host("127.0.0.1", 5006)
	_assert("Sender connected to local host port 5006", err == OK)
	
	var test_payload := {
		"bones": {
			"Hips": [0.0, 0.7071, 0.0, 0.7071]
		},
		"face": {
			"jawOpen": 0.85
		}
	}
	
	var json_str := JSON.stringify(test_payload)
	err = sender.put_packet(json_str.to_utf8_buffer())
	_assert("UDP packet sent", err == OK)
	
	# Attendre que le récepteur reçoive et traite le paquet dans sa boucle _process
	await create_timer(0.2).timeout
	
	# Vérifier les données décodées
	_assert("Bones rotation 'Hips' received", receiver._latest_bones_data.has("Hips"))
	if receiver._latest_bones_data.has("Hips"):
		var hips_rot: Quaternion = receiver._latest_bones_data["Hips"]
		_assert("Hips rotation is close to expected Quaternion", abs(hips_rot.y - 0.7071) < 0.01)
		
	_assert("Face blendshape 'jawOpen' received", receiver._latest_face_data.has("jawOpen"))
	if receiver._latest_face_data.has("jawOpen"):
		var jaw_val: float = receiver._latest_face_data["jawOpen"]
		_assert("jawOpen value matches", abs(jaw_val - 0.85) < 0.01)
		
	# Nettoyage
	receiver.stop_listening()
	receiver.queue_free()
	sender.close()

func _finish() -> void:
	print("\n======================================================================")
	print("Live Link Mocap Receiver Unit Tests Summary:")
	print("  Passed: %d" % _passed)
	print("  Failed: %d" % _failed)
	print("======================================================================")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
