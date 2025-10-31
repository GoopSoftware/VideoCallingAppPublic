import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'call_screen.dart';

import '../services/signaling_service.dart';

/*
Ui Version 1
*/

enum CallState { idle, connecting, inCall, incoming }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool loading = false;
  String? activeRoomId;
  CallState callState = CallState.idle;

  late AnimationController glowController;
  StreamSubscription<DatabaseEvent>? roomListener;

  //final TextEditingController roomController = TextEditingController();

  void initState() {
    super.initState();
    glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )
      ..repeat(reverse: true);

    listenForActiveRoom();
  }

  void listenForActiveRoom() async {
    roomListener = FirebaseDatabase.instance
        .ref('rooms')
        .onValue
        .listen((event,) {
      String? foundRoom;
      if (event.snapshot.exists) {
        for (final child in event.snapshot.children) {
          final data = child.value as Map?;
          if (data != null &&
              (data.containsKey('offer') || data.containsKey('created')) &&
              !data.containsKey('answer')) {
            foundRoom = child.key;
            break;
          }
        }
      }
      if (mounted) {
        setState(() {
          activeRoomId = foundRoom;
          if (foundRoom != null) {
            callState = CallState.incoming;
          } else if (callState == CallState.incoming) {
            callState = CallState.idle;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    roomListener?.cancel();
    glowController.dispose();
    super.dispose();
  }

  Future<void> handleCallButton() async {
    setState(() {
      loading = true;
      callState = CallState.connecting;
    });

    try {
      final activeRoomId = await SignalingService.checkForActiveRoom();

      final roomId =
          activeRoomId ??
              await SignalingService
                  .createRoomId(); // Create new if none exists

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CallScreen(roomId: roomId, isCaller: activeRoomId == null),
        ),
      ).then((_) {
        // Reset state when returning from call
        setState(() {
          callState = CallState.idle;
        });
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Color getButtonColor() {
    switch (callState) {
      case CallState.idle:
        return Colors.pinkAccent;
      case CallState.connecting:
        return Colors.orangeAccent;
      case CallState.inCall:
        return Colors.redAccent;
      case CallState.incoming:
        return Colors.greenAccent;
    }
  }

  String getStatusText() {
    switch (callState) {
      case CallState.idle:
        return "Ready to Call";
      case CallState.connecting:
        return "Connecting...";
      case CallState.inCall:
        return "In Call";
      case CallState.incoming:
        return "Incoming Call";
    }
  }

  Future<void> createRoom() async {
    setState(() => loading = true);
    try {
      final roomId = await SignalingService.createRoomId();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(roomId: roomId, isCaller: true),
        ),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final glowAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(glowController);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: glowAnimation,
              child: GestureDetector(
                onTap: handleCallButton,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: getButtonColor(),
                    boxShadow: [
                      BoxShadow(
                        color: getButtonColor().withOpacity(0.6),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.call,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              getStatusText(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (activeRoomId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Room: $activeRoomId",
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
