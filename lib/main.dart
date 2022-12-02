import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Sqflite demo'),
    );
  }
}

class Person implements Comparable {
  final int id;
  final String firstName;
  final String lastName;

  const Person({
    required this.id,
    required this.firstName,
    required this.lastName,
  });

  String get fullName => '$firstName, $lastName';

  Person.fromRow(Map<String, Object?> row)
      : id = row['ID'] as int,
        firstName = row['FIRST_NAME'] as String,
        lastName = row['LAST_NAME'] as String;

  @override
  // using covariant here because I expect the other object to be a Person.
  int compareTo(covariant Person other) {
    // to compare in chronological order
    // id.compareTo(other.id);
    // to compare in reverse chronological order.
    other.id.compareTo(id);
    throw UnimplementedError();
  }

  @override
  bool operator ==(covariant Person other) {
    return id == other.id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Person, id = $id, firstName = $firstName, lastName = $lastName';
  }
}

// creating the database.
class PersonDB {
  final String dbName;
  Database? _db;
  PersonDB({required this.dbName});
  List<Person> _persons = [];
  final _streamController = StreamController<List<Person>>.broadcast();

  // returns all intances of the Person class in the database table
  Future<List<Person>> _fetchPeople() async {
    final db = _db;
    if (db == null) {
      return [];
    }
    try {
      // executing a read query
      final read = await db.query('PEOPLE',
          distinct: true,
          columns: [
            'ID',
            'FIRST_NAME',
            'LAST_NAME',
          ],
          orderBy: 'ID');

      final people = read.map((row) => Person.fromRow(row)).toList();
      return people;
    } catch (e) {
      print('Error fetching people = $e');
      return [];
    }
  }

  // opening the database
  Future<bool> open() async {
    if (_db != null) {
      return true;
    }
    // get path to the database
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$dbName';

    try {
      final db = await openDatabase(path);
      _db = db;

      // creating the table
      const create = '''CREATE TABLE IF NOT EXISTS PEOPLE(
        ID INTEGER PRIMARY KEY AUTOINCREMENT,
        FIRST_NAME STRING NOT NULL,
        LAST_NAME STRING NOT NULL
      )''';

      await db.execute(create);

      // read all existing Person objects from the db
      _persons = await _fetchPeople();
      _streamController.add(_persons);
      return true;
    } catch (e) {
      print('Error = $e');
      return false;
    }
  }

  // C in CRUD
  // creating the person in the database.
  Future<bool> create(String firstName, String lastName) async {
    final db = _db;
    if (db == null) {
      return false;
    }

    try {
      final id = await db.insert(
        'PEOPLE',
        {
          'FIRST_NAME': firstName,
          'LAST_NAME': lastName,
        },
      );

      final person = Person(
        id: id,
        firstName: firstName,
        lastName: lastName,
      );

      _persons.add(person);
      _streamController.add(_persons);
      return true;
    } catch (e) {
      print('Error in creating person = $e');
      return false;
    }
  }

  // D in CRUD
  // deleting person from the database.
  Future<bool> delete(Person person) async {
    final db = _db;
    if (db == null) {
      return false;
    }
    try {
      final deletedCount = await db.delete(
        'PEOPLE',
        where: 'ID = ?',
        whereArgs: [person.id],
      );
      if (deletedCount == 1) {
        //making sure one row is deleted
        _persons.remove(person);
        _streamController.add(_persons);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print('Deletion failed with error $e');
      return false;
    }
  }

  Future<bool> update(Person person) async {
    final db = _db;
    if (db == null) {
      return false;
    }
    try {
      final updateCount = await db.update(
        'PEOPLE',
        {
          'FIRST_NAME': person.firstName,
          'LAST_NAME': person.firstName,
        },
        where: 'ID = ?',
        whereArgs: [person.id],
      );

      if(updateCount == 1){
        _persons.removeWhere((other) => other.id == person.id);
        _persons.add(person);
        _streamController.add(_persons);
        return true;
      }else{
        return false;
      }
    } catch (e) {
      print('Failed to update item error = $e');
      return false;
    }
  }

  Future<bool> close() async {
    final db = _db;
    if (db == null) {
      return false;
    }
    await db.close();
    return true;
  }

  Stream<List<Person>> all() =>
      _streamController.stream.map((persons) => persons..sort());
}

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final PersonDB _crudStorage;

  @override
  void initState() {
    _crudStorage = PersonDB(dbName: 'db.sqlite');
    _crudStorage.open();
    super.initState();
  }

  @override
  void dispose() {
    _crudStorage.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.title),
      ),
      body: StreamBuilder(
          stream: _crudStorage.all(),
          builder: (context, snapshot) {
            switch (snapshot.connectionState) {
              case ConnectionState.active:
              case ConnectionState.waiting:
                if (snapshot.data == null) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                final people = snapshot.data as List<Person>;
                return Column(
                  children: [
                    ComposeWidget(
                      onCompose: (firstName, lastName) async {
                        await _crudStorage.create(firstName, lastName);
                      },
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: people.length,
                        itemBuilder: (context, index) {
                          final person = people[index];
                          return ListTile(
                            onTap: () async {
                              final editedPerson = await showUpdateDialog(
                                context,
                                person,
                              );
                              if (editedPerson != null) {
                                await _crudStorage.update(editedPerson);
                              }
                            },
                            title: Text(person.fullName),
                            subtitle: Text('ID : ${person.id}'),
                            trailing: TextButton(
                              onPressed: () async {
                                final shouldDelete =
                                    await showDeleteDialog(context);
                                if (shouldDelete) {
                                  await _crudStorage.delete(person);
                                }
                              },
                              child: const Icon(
                                  Icons.disabled_by_default_rounded,
                                  color: Colors.red),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              default:
                return const Center(
                  child: CircularProgressIndicator(),
                );
            }
          }),
    );
  }
}

Future<bool> showDeleteDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: const Text('Delete'),
          ),
        ],
      );
    },
  ).then((value) {
    if (value is bool) {
      return value;
    } else {
      return false;
    }
  });
}

final _firstNameController = TextEditingController();
final _lastNameController = TextEditingController();
Future<Person?> showUpdateDialog(BuildContext context, Person person) {
  _firstNameController.text = person.firstName;
  _lastNameController.text = person.lastName;
  return showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your updated values here:'),
            TextField(
              controller: _firstNameController,
            ),
            TextField(
              controller: _lastNameController,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(null);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final editedPerson = Person(
                  id: person.id,
                  firstName: _firstNameController.text,
                  lastName: _lastNameController.text);
              Navigator.of(context).pop(editedPerson);
            },
            child: Text('Save'),
          ),
        ],
      );
    },
  ).then((value) {
    if (value is Person) {
      return value;
    } else {
      return null;
    }
  });
}

typedef OnCompose = void Function(String firstName, String lastName);

class ComposeWidget extends StatefulWidget {
  final OnCompose onCompose;
  const ComposeWidget({Key? key, required this.onCompose}) : super(key: key);

  @override
  State<ComposeWidget> createState() => _ComposeWidgetState();
}

class _ComposeWidgetState extends State<ComposeWidget> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;

  @override
  void initState() {
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          TextField(
            controller: _firstNameController,
            decoration: const InputDecoration(hintText: 'Enter first name'),
          ),
          TextField(
            controller: _lastNameController,
            decoration: const InputDecoration(hintText: 'Enter last name'),
          ),
          TextButton(
            onPressed: () {
              final firstName = _firstNameController.text;
              final lastName = _lastNameController.text;
              widget.onCompose(firstName, lastName);
              _firstNameController.text = '';
              _lastNameController.text = '';
            },
            child: const Text(
              'Add to list',
              style: TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}
