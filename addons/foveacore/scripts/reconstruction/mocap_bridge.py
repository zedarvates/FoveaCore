#!/usr/bin/env python3
import sys
import os
import json
import time
import argparse
import socket
import math

# Try importing MediaPipe and OpenCV, fallback to simulation mode if unavailable
MEDIAPIPE_AVAILABLE = False
try:
    import cv2
    import mediapipe as mp
    import numpy as np
    MEDIAPIPE_AVAILABLE = True
except ImportError:
    pass

class MocapBridge:
    def __init__(self, args):
        self.args = args
        self.running = False
        self.sock = None
        
        if args.stream:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            print(f"# Streaming mocap data to {args.stream}:{args.port} via UDP")

    def run(self):
        self.running = True
        
        # Decide between real camera/video tracking or simulated data
        if self.args.simulate or not MEDIAPIPE_AVAILABLE:
            if not MEDIAPIPE_AVAILABLE:
                print("# MediaPipe or OpenCV not installed. Running in SIMULATION mode.", file=sys.stderr)
            self._run_simulation()
        else:
            self._run_tracking()

    def _calculate_quaternion_from_vectors(self, v_from, v_to):
        """Calculates a rotation quaternion from one vector to another."""
        v_from = v_from / np.linalg.norm(v_from)
        v_to = v_to / np.linalg.norm(v_to)
        
        dot = np.dot(v_from, v_to)
        if dot > 0.9999:
            return [0.0, 0.0, 0.0, 1.0]
        elif dot < -0.9999:
            # Opposite vectors: rotate 180 degrees around any orthogonal axis
            ortho = np.array([1.0, 0.0, 0.0])
            if abs(v_from[0]) > 0.9:
                ortho = np.array([0.0, 1.0, 0.0])
            axis = np.cross(v_from, ortho)
            axis = axis / np.linalg.norm(axis)
            return [float(axis[0]), float(axis[1]), float(axis[2]), 0.0]
            
        axis = np.cross(v_from, v_to)
        axis_len = np.linalg.norm(axis)
        if axis_len < 1e-6:
            return [0.0, 0.0, 0.0, 1.0]
        axis = axis / axis_len
        
        # Angle of rotation
        angle = math.acos(dot)
        half_angle = angle * 0.5
        sin_half = math.sin(half_angle)
        
        return [
            float(axis[0] * sin_half),
            float(axis[1] * sin_half),
            float(axis[2] * sin_half),
            float(math.cos(half_angle))
        ]

    def _run_tracking(self):
        """Standard MediaPipe Holistic tracking loop."""
        mp_holistic = mp.solutions.holistic
        
        # Determine source (webcam index or video file path)
        source = self.args.input
        if source.isdigit():
            source = int(source)
            
        cap = cv2.VideoCapture(source)
        if not cap.isOpened():
            print(f"Error: Could not open input source {source}", file=sys.stderr)
            sys.exit(1)
            
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        
        mocap_frames = []
        fps_delay = 1.0 / self.args.fps
        
        with mp_holistic.Holistic(
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        ) as holistic:
            while cap.isOpened() and self.running:
                start_time = time.time()
                ret, frame = cap.read()
                if not ret:
                    break
                    
                # Flip frame horizontally for selfie/webcam mode
                if isinstance(source, int):
                    frame = cv2.flip(frame, 1)
                    
                # Process image
                rgb_image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                results = holistic.process(rgb_image)
                
                # Format frame data
                frame_data = {
                    "timestamp": time.time(),
                    "face": {},
                    "bones": {}
                }
                
                # 1. Face Blendshapes Solver (ARKit subset)
                if results.face_landmarks:
                    landmarks = results.face_landmarks.landmark
                    
                    # 1.1 Jaw open (distance between upper and lower inner lips)
                    # Inner lip top: landmark 13, bottom: landmark 14
                    jaw_dist = abs(landmarks[13].y - landmarks[14].y) * height
                    frame_data["face"]["jawOpen"] = float(np.clip(jaw_dist / 15.0, 0.0, 1.0))
                    
                    # 1.2 Eye blinking (left/right distance between upper/lower eyelid)
                    # Left eye eyelids: top: 386, bottom: 374
                    # Right eye eyelids: top: 159, bottom: 145
                    left_eye_dist = abs(landmarks[386].y - landmarks[374].y) * height
                    right_eye_dist = abs(landmarks[159].y - landmarks[145].y) * height
                    
                    frame_data["face"]["eyeBlinkLeft"] = float(np.clip(1.0 - (left_eye_dist / 6.0), 0.0, 1.0))
                    frame_data["face"]["eyeBlinkRight"] = float(np.clip(1.0 - (right_eye_dist / 6.0), 0.0, 1.0))
                    
                    # 1.3 Smile (mouth width and corners up/down)
                    # Mouth corners: left: 291, right: 61. Center: 0
                    mouth_w = abs(landmarks[291].x - landmarks[61].x) * width
                    mouth_center_y = (landmarks[291].y + landmarks[61].y) * 0.5
                    mouth_top_y = landmarks[0].y
                    smile_val = (mouth_center_y - mouth_top_y) * height
                    
                    frame_data["face"]["mouthSmileLeft"] = float(np.clip(smile_val / 8.0, 0.0, 1.0))
                    frame_data["face"]["mouthSmileRight"] = float(np.clip(smile_val / 8.0, 0.0, 1.0))
                    
                    # 1.4 Brows (distance between eyebrow and pupil/eye center)
                    # Left brow inner: 285, Right brow inner: 55
                    left_brow = landmarks[285].y * height
                    right_brow = landmarks[55].y * height
                    frame_data["face"]["browInnerUp"] = float(np.clip((0.2 - (left_brow + right_brow)*0.001) * 5.0, 0.0, 1.0))

                # 2. Body skeletal tracking (quaternions mapping)
                if results.pose_landmarks:
                    landmarks = results.pose_landmarks.landmark
                    
                    # Convert to numpy array for vector operations
                    joints = {}
                    for i, lm in enumerate(landmarks):
                        # MediaPipe coordinates: X: right-to-left, Y: top-to-bottom, Z: depth
                        # Convert to Godot space (X: right, Y: up, Z: back)
                        joints[i] = np.array([lm.x, -lm.y, -lm.z])
                        
                    # Calculate arm rotations (Left Arm: 11 to 13, Left Forearm: 13 to 15)
                    if 11 in joints and 13 in joints:
                        left_arm_dir = joints[13] - joints[11]
                        frame_data["bones"]["LeftArm"] = self._calculate_quaternion_from_vectors(
                            np.array([-1.0, 0.0, 0.0]), left_arm_dir
                        )
                    if 13 in joints and 15 in joints:
                        left_forearm_dir = joints[15] - joints[13]
                        frame_data["bones"]["LeftForearm"] = self._calculate_quaternion_from_vectors(
                            np.array([-1.0, 0.0, 0.0]), left_forearm_dir
                        )
                        
                    # Right arm (Right Arm: 12 to 14, Right Forearm: 14 to 16)
                    if 12 in joints and 14 in joints:
                        right_arm_dir = joints[14] - joints[12]
                        frame_data["bones"]["RightArm"] = self._calculate_quaternion_from_vectors(
                            np.array([1.0, 0.0, 0.0]), right_arm_dir
                        )
                    if 14 in joints and 16 in joints:
                        right_forearm_dir = joints[16] - joints[14]
                        frame_data["bones"]["RightForearm"] = self._calculate_quaternion_from_vectors(
                            np.array([1.0, 0.0, 0.0]), right_forearm_dir
                        )

                # Send or save frame
                self._handle_frame(frame_data, mocap_frames)
                
                # Maintain constant FPS
                elapsed = time.time() - start_time
                if elapsed < fps_delay:
                    time.sleep(fps_delay - elapsed)

        cap.release()
        
        # Save batch output if file path specified
        if self.args.output and mocap_frames:
            self._save_output(mocap_frames)

    def _run_simulation(self):
        """Simulation mode generating sinusoidal face and arm movements."""
        mocap_frames = []
        fps_delay = 1.0 / self.args.fps
        start_sim = time.time()
        
        # Simulation duration
        duration = self.args.duration if self.args.duration > 0 else 10.0
        frame_count = int(duration * self.args.fps)
        
        print(f"# Simulating mocap data for {duration}s ({frame_count} frames)")
        
        for f in range(frame_count):
            if not self.running:
                break
                
            t = (time.time() - start_sim)
            
            # Simple oscillators for animation parameters
            jaw_val = (math.sin(t * 3.0) + 1.0) * 0.4  # Jaw opening/closing
            smile_val = (math.cos(t * 2.0) + 1.0) * 0.5 # Smiling
            left_eye_blink = 1.0 if (int(t) % 3 == 0 and (t % 1.0) < 0.15) else 0.0
            
            # Oscillating left arm up and down
            arm_angle = math.sin(t * 2.0) * 0.8
            # Quaternion rotation around Z axis for left arm
            l_arm_q = [0.0, 0.0, float(math.sin(arm_angle/2.0)), float(math.cos(arm_angle/2.0))]
            
            frame_data = {
                "timestamp": time.time(),
                "face": {
                    "jawOpen": float(jaw_val),
                    "eyeBlinkLeft": float(left_eye_blink),
                    "eyeBlinkRight": float(left_eye_blink),
                    "mouthSmileLeft": float(smile_val),
                    "mouthSmileRight": float(smile_val),
                    "browInnerUp": float((math.sin(t * 1.5) + 1.0) * 0.3)
                },
                "bones": {
                    "LeftArm": l_arm_q,
                    "LeftForearm": [0.0, 0.0, 0.0, 1.0],
                    "RightArm": [0.0, 0.0, 0.0, 1.0],
                    "RightForearm": [0.0, 0.0, 0.0, 1.0]
                }
            }
            
            self._handle_frame(frame_data, mocap_frames)
            time.sleep(fps_delay)
            
        if self.args.output and mocap_frames:
            self._save_output(mocap_frames)

    def _handle_frame(self, frame_data, mocap_frames):
        """Sends frame over UDP or collects it for disk saving."""
        if self.sock and self.args.stream:
            try:
                payload = json.dumps(frame_data).encode("utf-8")
                self.sock.sendto(payload, (self.args.stream, self.args.port))
            except Exception as e:
                print(f"# UDP Send error: {e}", file=sys.stderr)
                
        if self.args.output:
            mocap_frames.append(frame_data)

    def _save_output(self, frames):
        try:
            with open(self.args.output, "w") as f:
                json.dump({"frames": frames}, f, indent=2)
            print(f"# Successfully saved {len(frames)} mocap frames to {self.args.output}")
        except Exception as e:
            print(f"Error: Failed to save to {self.args.output}: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="FoveaEngine Markerless Motion Capture Bridge")
    parser.add_argument("--input", default="0", help="Webcam index (0) or input video path")
    parser.add_argument("--output", default="", help="JSON file output path to write recorded mocap")
    parser.add_argument("--stream", default="", help="Target IP for real-time UDP streaming (e.g. 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8766, help="Target UDP port (default: 8766)")
    parser.add_argument("--fps", type=int, default=30, help="Target processing FPS")
    parser.add_argument("--simulate", action="store_true", help="Force simulation mode without camera/MediaPipe")
    parser.add_argument("--duration", type=float, default=10.0, help="Simulation duration in seconds")
    
    args = parser.parse_args()
    
    bridge = MocapBridge(args)
    try:
        bridge.run()
    except KeyboardInterrupt:
        print("# Stopping Mocap Bridge...")
        bridge.running = False

if __name__ == "__main__":
    main()
