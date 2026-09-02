import 'package:flutter/material.dart';
import 'package:guitar_tuner_app/tuner/recorder_engine.dart';

class TestRecordPage extends StatefulWidget {
  const TestRecordPage({super.key});

  @override
  State<TestRecordPage> createState() => _TestRecordPageState();
}

class _TestRecordPageState extends State<TestRecordPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:const Text("Test Page"),

        actions: [
          TextButton(onPressed: (){
            startTuner();
          }, child:const Text("Start"))
        ],
      ),
      body:const Center(
        child: Text("Test your data here.")
      ),
    );
  }
}
