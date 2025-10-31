import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/signaling_service.dart';

class CallScreen extends StatefulWidget {
  final String roomId;
  final bool isCaller; // true = createRoom, false = joinRoom
  const CallScreen({super.key, required this.roomId, required this.isCaller});

  @override
  State<CallScreen> createState() => CallScreenState();
}

class CallScreenState extends State<CallScreen> {
  // We create 2 renderers, 1 for user and 1 for peer
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  late SignalingService signaling;
  bool remoteEnded = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await Permission.camera.request();
    await Permission.microphone.request();

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    signaling = SignalingService(
      roomId: widget.roomId,
      isCaller: widget.isCaller,
      onAddRemoteStream: (stream) =>
          setState(() => remoteRenderer.srcObject = stream),
    );

    await signaling.initLocalMedia(localRenderer);

    setState(() {});

    await signaling.startConnection();

    FirebaseDatabase.instance
        .ref('rooms/${widget.roomId}/ended')
        .onValue
        .listen((event) async {
      if (event.snapshot.value == true && mounted && !remoteEnded) {
        setState(() => remoteEnded = true);

        await signaling.close();

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: Text(
              "Call Ended",
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 800));

        if (!mounted) return;
        Navigator.of(context)
          ..pop() // close dialog
          ..pop(); // leave CallScreen -> back to Home

        await localRenderer.dispose();
        await remoteRenderer.dispose();
      }
    });
  }

  Future<void> hangUp() async {
    await signaling.endRoom(widget.roomId);
    await signaling.close();
    await Future.delayed(const Duration(milliseconds: 800));
    await signaling.deleteRoom(widget.roomId);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    signaling.close();
    signaling.deleteRoom(widget.roomId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          RTCVideoView(
            remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Positioned(
            right: 16,
            bottom: 16,
            width: 120,
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RTCVideoView(localRenderer, mirror: true),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: FloatingActionButton(
                backgroundColor: Colors.red,
                onPressed: hangUp,
                child: const Icon(Icons.call_end),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
