import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingService {
  final String roomId;
  final bool isCaller;
  final Function(MediaStream stream) onAddRemoteStream;

  late RTCPeerConnection peerConnection;
  late MediaStream localStream;
  final _db = FirebaseDatabase.instance.ref();

  SignalingService({
    required this.roomId,
    required this.isCaller,
    required this.onAddRemoteStream,
  });

  Future<void> close() async {
    peerConnection.close();
    localStream.dispose();
  }

  static Future<String> createRoomId() async {
    final id = Random().nextInt(999999).toString().padLeft(6, '0');
    await FirebaseDatabase.instance.ref("rooms/$id").set({'created': true});
    return id;
  }

  Future<void> initLocalMedia(RTCVideoRenderer localRenderer) async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });
    localRenderer.srcObject = localStream;
  }

  Future<void> startConnection() async {
    peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });

    // Add local tracks
    for (var track in localStream.getTracks()) {
      await peerConnection.addTrack(track, localStream);
    }

    // Remote media
    peerConnection.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        onAddRemoteStream(event.streams[0]);
      }
    };

    // ICE out
    peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        _db.child('rooms/$roomId/candidates').push().set({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    // create else join
    if (isCaller) {
      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      await _db.child('rooms/$roomId/offer').set({
        'sdp': offer.sdp,
        'type': offer.type,
      });

      _db.child('rooms/$roomId/answer').onValue.listen((event) async {
        if (event.snapshot.exists) {
          final ans = event.snapshot.value as Map;
          await peerConnection.setRemoteDescription(
            RTCSessionDescription(ans['sdp'], ans['type']),
          );
        }
      });
    } else {
      final offerSnap = await _db.child('rooms/$roomId/offer').get();
      final offer = RTCSessionDescription(
        offerSnap.child('sdp').value as String,
        'offer',
      );
      await peerConnection.setRemoteDescription(offer);

      final answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);
      await _db.child('rooms/$roomId/answer').set({
        'sdp': answer.sdp,
        'type': answer.type,
      });
    }

    // ICE in
    _db.child('rooms/$roomId/candidates').onChildAdded.listen((event) {
      final data = event.snapshot.value as Map;
      peerConnection.addCandidate(
        RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        ),
      );
    });

    // listen for room end flag
    _db.child('rooms/$roomId/ended').onValue.listen((event) async {
      if (event.snapshot.value == true) {
        await peerConnection.close();
      }
    });

    // (Optional) log ICE state to confirm success
    peerConnection.onIceConnectionState = (state) {
      print('ICE state: $state'); // look for Connected
    };
  }

  // creates a room and returns its ID
  Future<String> createRoom(Map<String, dynamic> offerData) async {
    final roomRef = _db.child('rooms').push();
    await roomRef.set({'offer': offerData, 'createdAt': ServerValue.timestamp});
    return roomRef.key!;
  }

  // Join a room by ID and upload answerData
  Future<void> joinRoom(String roomId, Map<String, dynamic> answerData) async {
    final roomRef = _db.child('rooms/$roomId');
    await roomRef.update({
      'answer': answerData,
      'joinedAt': ServerValue.timestamp,
    });
  }

  // Listen for changes in the room for debugging
  Stream<DatabaseEvent> listenToRoom(String roomId) {
    return _db.child('rooms/$roomId').onValue;
  }

  // clean up when the call ends
  Future<void> deleteRoom(String roomId) async {
    await _db.child('rooms/$roomId').remove();
  }

  Future<void> endRoom(String roomId) async {
    await _db.child('rooms/$roomId').update({'ended': true});
  }

  // Checks Firebase to see if a call room already exists.
  // Returns the first available roomId if one is active, or null otherwise.
  static Future<String?> checkForActiveRoom() async {
    final db = FirebaseDatabase.instance.ref("rooms");
    final snapshot = await db.get();

    if (!snapshot.exists) return null;

    // Loop through children to find any offer that hasn’t been answered yet
    for (final child in snapshot.children) {
      final data = child.value as Map?;
      if (data != null &&
          data.containsKey('offer') &&
          !data.containsKey('answer')) {
        // Room with an offer but no answer = incoming call waiting to be joined
        return child.key;
      }
    }

    return null; // No active call
  }
}
