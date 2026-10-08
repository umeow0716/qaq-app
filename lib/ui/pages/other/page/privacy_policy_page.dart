import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:qaq_app/src/config/app_colors.dart';
import 'package:qaq_app/src/config/app_link.dart';
import 'package:qaq_app/src/connector/network.dart';
import 'package:qaq_app/src/r.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(R.current.PrivacyPolicy)),
    body: FutureBuilder<String>(
      future: dio.get<String>(AppLink.privacyPolicyUrlString).then((response) => response.data!.trim()),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Markdown(selectable: true, data: snapshot.data ?? '');
        } else if (snapshot.hasError) {
          return const Center(child: Icon(Icons.error));
        }
        return const Center(child: SpinKitDoubleBounce(color: AppColors.mainColor));
      },
    ),
  );
}
