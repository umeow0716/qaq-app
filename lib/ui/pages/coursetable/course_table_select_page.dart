import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qaq_app/src/r.dart';
import 'package:qaq_app/src/store/local_storage.dart';

class CourseTableSelectPage extends StatefulWidget {
  const CourseTableSelectPage({super.key, this.onDeleted});

  final Future<void> Function(String studentId)? onDeleted;

  @override
  State<CourseTableSelectPage> createState() => _CourseTableSelectPageState();
}

class _CourseTableSelectPageState extends State<CourseTableSelectPage> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deleteImportedPerson(String studentId) async {
    await LocalStorage.instance.deleteImportedCourseTableSharePerson(studentId);
    await widget.onDeleted?.call(studentId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final storage = LocalStorage.instance;
    final account = storage.getAccount().trim();
    final ownName = storage.getUserInfo().givenName.trim();
    final imported = storage.getImportedCourseTableSharePeople().where((person) => person.matches(_keyword)).toList()
      ..sort((a, b) => a.studentId.compareTo(b.studentId));

    return Scaffold(
      appBar: AppBar(title: Text(R.current.courseTableSelectTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                onChanged: (value) => setState(() => _keyword = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: R.current.courseTableSearchHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text('$account（$ownName）'),
                    onTap: () => Get.back<String>(result: account),
                  ),
                  const Divider(height: 1),
                  for (final person in imported)
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: Text('${person.studentId}（${person.name}）'),
                      trailing: IconButton(
                        tooltip: R.current.delete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteImportedPerson(person.studentId),
                      ),
                      onTap: () => Get.back<String>(result: person.studentId),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
