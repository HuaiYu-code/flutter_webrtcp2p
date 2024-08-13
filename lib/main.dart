import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter WebRTC Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter WebRTC Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}


class _MyHomePageState extends State<MyHomePage> {
  final _localVideoRenderer = RTCVideoRenderer();
  final _remoteVideoRenderer = RTCVideoRenderer();
  final sdpController = TextEditingController();

  bool _offer = false;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  IOWebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    
    initRenderer().then((_) => _createPeerConnection().then((pc) {
      setState(() {
        _peerConnection = pc;
      });
    }));
    _connectToServer();
  }

  @override
  void dispose() async {
    await _localVideoRenderer.dispose();
    await _remoteVideoRenderer.dispose();
    sdpController.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  void _handleError(Object error, [StackTrace? stackTrace]) {
    debugPrint('Error: $error');
    if (stackTrace != null) {
      debugPrint('StackTrace: $stackTrace');
    }
  }

  void _connectToServer() {
    _channel = IOWebSocketChannel.connect('ws://192.168.9.188:8080');
    _channel?.stream.handleError(_handleError).listen((message) {
      print('Received message: $message');
      var data = json.decode(message);
      print(data['type']);
      switch (data['type']) {
        case 'offer':
          _onOffer(data['sdp']);
          break;
        case 'answer':
          _onAnswer(data['sdp']);
          break;
        case 'candidate':
          _onCandidate(data['candidate']);
          break;
      }
    });
  }


  void _sendToServer(Map<String, dynamic> message) {
    _channel?.sink.add(json.encode(message));
  }

  void _onOffer(String sdp) async {
    await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'));
    _createAnswer();
  }

  void _onAnswer(String sdp) async {
    await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(sdp, 'answer'));
  }

  void _onCandidate(dynamic candidate) async {
    var iceCandidate = RTCIceCandidate(
      candidate['candidate'],
      candidate['sdpMid'],
      candidate['sdpMlineIndex'],
    );
    await _peerConnection?.addCandidate(iceCandidate);
  }

  initRenderer() async {
    await _localVideoRenderer.initialize();
    await _remoteVideoRenderer.initialize();
  }


  _getDisplayMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'video': {
        'cursor': 'always' // 可选参数，控制是否显示鼠标光标
      },
      'audio': true // 这里可以设置是否包含音频
    };

    MediaStream stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
    _localVideoRenderer.srcObject = stream;
    return stream;
  }

  _getUserMedia() async {
    Map<String, dynamic> mediaConstraints = {
      'audio': {
        "echoCancellation": true,
        "autoGainControl": true,
        "noiseSuppression": true
      },
      'video': {
        'facingMode': 'user', // 使用前置摄像头
        // 'width': 1280,
        // 'height': 720,
        'frameRate': 30
      },
    };

    // mediaConstraints['video']['width'] = 1920;
    // mediaConstraints['video']['height'] = 1080;

    MediaStream stream =
    await navigator.mediaDevices.getUserMedia(mediaConstraints);

    _localVideoRenderer.srcObject = stream;
    return stream;
  }


  Future<RTCPeerConnection> _createPeerConnection() async {
    try {
      Map<String, dynamic> configuration = {
        "iceServers": [
          {"url": "stun:stun.l.google.com:19302"},
        ]
      };

      final Map<String, dynamic> offerSdpConstraints = {
        "mandatory": {
          "OfferToReceiveAudio": true,
          "OfferToReceiveVideo": true,
        },
        "optional": [],
      };

      _localStream = await _getUserMedia();
      // _localStream = await _getDisplayMedia();

      RTCPeerConnection pc =
      await createPeerConnection(configuration, offerSdpConstraints);

      // 使用 addTrack 代替 addStream
      _localStream!.getTracks().forEach((track) async{
        await pc.addTrack(track, _localStream!);
      });

      pc.onIceCandidate = (e) {
        print('onIceCandidate');
        if (e.candidate != null) {
          _sendToServer({
            'type': 'candidate',
            'candidate': {
              'candidate': e.candidate.toString(),
              'sdpMid': e.sdpMid.toString(),
              'sdpMlineIndex': e.sdpMLineIndex,
            }
          });
        }
      };

      pc.onIceConnectionState = (e) {
        print(e);
      };

      pc.onTrack = (event) {
        print('onTrack: ${event.track.kind},');
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          print('onTrack:');
          setState(() {
            _remoteVideoRenderer.srcObject = event.streams[0];
          });
        }
      };

      return pc;
    } on Exception catch (e) {
      _handleError('Failed to create PeerConnection: $e');
      rethrow; // 重新抛出异常，以便在更高层级处理
    }
  }

  void _createOffer() async {
    RTCSessionDescription description =
    await _peerConnection!.createOffer({
        'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
    });
    var session = parse(description.sdp.toString());
    print(json.encode(session));
    _offer = true;

    _peerConnection!.setLocalDescription(description);
    _sendToServer({
      'type': 'offer',
      'sdp': description.sdp,
    });
  }

  void _createAnswer() async {
    RTCSessionDescription description =
    await _peerConnection!.createAnswer({'offerToReceiveVideo': 1});

    var session = parse(description.sdp.toString());
    print(json.encode(session));

    _peerConnection!.setLocalDescription(description);
    _sendToServer({
      'type': 'answer',
      'sdp': description.sdp,
    });
  }

  void _setRemoteDescription() async {
    String jsonString = sdpController.text;
    dynamic session = await jsonDecode(jsonString);

    String sdp = write(session, null);

    RTCSessionDescription description =
    RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
    print(description.toMap());

    await _peerConnection!.setRemoteDescription(description);
  }

  void _addCandidate() async {
    String jsonString = sdpController.text;
    dynamic session = await jsonDecode(jsonString);
    print(session['candidate']);
    dynamic candidate = RTCIceCandidate(
        session['candidate'], session['sdpMid'], session['sdpMlineIndex']);
    await _peerConnection!.addCandidate(candidate);
  }

  SizedBox videoRenderers() => SizedBox(
    height: 210,
    child: Row(children: [
      Flexible(
        child: Container(
          key: const Key('local'),
          margin: const EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
          decoration: const BoxDecoration(color: Colors.black),
          child: RTCVideoView(_localVideoRenderer),
        ),
      ),
      Flexible(
        child: Container(
          key: const Key('remote'),
          margin: const EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
          decoration: const BoxDecoration(color: Colors.black),
          child: RTCVideoView(_remoteVideoRenderer),
        ),
      ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          videoRenderers(),
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.5,
                  child: TextField(
                    controller: sdpController,
                    keyboardType: TextInputType.multiline,
                    maxLines: 4,
                    maxLength: TextField.noMaxLength,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _createOffer,
                    child: const Text("Offer"),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  ElevatedButton(
                    onPressed: _createAnswer,
                    child: const Text("Answer"),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  ElevatedButton(
                    onPressed: _setRemoteDescription,
                    child: const Text("Set Remote Description"),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  ElevatedButton(
                    onPressed: _addCandidate,
                    child: const Text("Set Candidate"),
                  ),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }
}