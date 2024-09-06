import 'dart:convert';

List<String>? parseAssignedNamesFromString(String? assignedNamesJsonString) {
  if (assignedNamesJsonString == null || assignedNamesJsonString.isEmpty) {
    return null;
  }

  try {
    final Map<String, dynamic> jsonData = jsonDecode(assignedNamesJsonString);
    final List<dynamic> assignedNamesList = jsonData['assignedNames'];

    return assignedNamesList.map((name) => name.toString()).toList();
  } catch (e) {
    return null;
  }
}

//
