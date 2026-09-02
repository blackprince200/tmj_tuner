import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashPage extends StatefulWidget{
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {

  @override
  void initState(){
    super.initState();

    Timer(const Duration(seconds: 3),(){
      if(!mounted){
        return;
      }
      context.replace("/test_record_page");
    });
  }

  @override
  Widget build(BuildContext context ){
    return const Scaffold(
      body: Text("SplashPage"),
    );
  }
}