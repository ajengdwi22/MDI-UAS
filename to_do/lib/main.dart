import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/google_calendar_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'login_page.dart';
import 'signup_page.dart';
import 'add_edit_task_page.dart';
import 'calendar_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBnlyCUNXFTbKf-DUFyEB8D6E94L4edbHw",
        authDomain: "todolist-ac951.firebaseapp.com",
        projectId: "todolist-ac951",
        storageBucket: "todolist-ac951.appspot.com",
        messagingSenderId: "610679045814",
        appId: "1:610679045814:web:36af15a16ae857dac23017",
        measurementId: "G-SKNMP7GX28",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      routes: {
        '/': (context) => AuthWrapper(),
        '/main': (context) => HomeScreen(),
        '/login': (context) => LoginPage(),
        '/signup': (context) => SignUpPage(),
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return HomeScreen();
        }
        return LoginPage();
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final TextEditingController _controller = TextEditingController();
  int updateIndex = -1;
  String? editingTodoId;
  List<Map<String, dynamic>> todoList = [];

  User? get currentUser => FirebaseAuth.instance.currentUser;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/calendar'],
  );
  final GoogleCalendarService _calendarService = GoogleCalendarService();

  void _onNavTapped(int index) {
    if (index == 2) {
      // Navigasi ke halaman tambah task
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => AddEditTaskPage(isEdit: false)),
      ).then((value) {
        if (value == true) fetchTodos();
      });
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    fetchTodos();
    fetchDisplayName();
  }

  String? displayName;

  Future<void> fetchDisplayName() async {
    if (currentUser == null) return;
    // Mengambil dari 'users' (jika ada, dari pendaftaran manual)
    DocumentSnapshot userDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .get();

    // Mengambil dari 'todoapp' (jika ada, dari pendaftaran dengan Google)
    DocumentSnapshot todoAppDoc =
        await FirebaseFirestore.instance
            .collection('todoapp')
            .doc(currentUser!.uid)
            .get();

    setState(() {
      // Prioritaskan username dari koleksi 'users' atau 'todoapp'
      if (userDoc.exists && (userDoc.data() as Map).containsKey('username')) {
        displayName = userDoc.get('username');
      } else if (todoAppDoc.exists &&
          (todoAppDoc.data() as Map).containsKey('username')) {
        displayName = todoAppDoc.get('username');
      } else {
        // Fallback ke displayName dari auth provider (misal: Google) atau email
        displayName = currentUser!.displayName ?? currentUser!.email ?? '-';
      }
    });
  }

  Future<void> fetchTodos() async {
    if (currentUser == null) return;
    final snapshot =
        await FirebaseFirestore.instance
            .collection('todoapp')
            .doc(currentUser!.uid)
            .collection('todos')
            .orderBy('createdAt', descending: false)
            .get();
    setState(() {
      todoList =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    });
  }

  Future<void> addList(String task) async {
    if (currentUser == null || task.trim().isEmpty) return;
    await FirebaseFirestore.instance
        .collection('todoapp')
        .doc(currentUser!.uid)
        .collection('todos')
        .add({'task': task, 'isDone': false, 'createdAt': DateTime.now()});
    _controller.clear();
    fetchTodos();
  }

  Future<void> updateListItem(String task, int index) async {
    if (currentUser == null || editingTodoId == null) return;
    final todoId = editingTodoId;
    await FirebaseFirestore.instance
        .collection('todoapp')
        .doc(currentUser!.uid)
        .collection('todos')
        .doc(todoId)
        .update({'task': task});
    updateIndex = -1;
    editingTodoId = null;
    _controller.clear();
    fetchTodos();
  }

  Future<void> deleteItem(int index) async {
    if (currentUser == null) return;
    final todoId = todoList[index]['id'];
    final eventId = todoList[index]['eventId'];
    // Hapus event Google Calendar hanya jika user login Google
    GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
    googleUser ??= await _googleSignIn.signIn();
    if (eventId != null &&
        eventId.toString().isNotEmpty &&
        googleUser != null) {
      try {
        await _calendarService.deleteEvent(eventId, googleUser);
      } catch (e) {}
    }
    await FirebaseFirestore.instance
        .collection('todoapp')
        .doc(currentUser!.uid)
        .collection('todos')
        .doc(todoId)
        .delete();
    fetchTodos();
  }

  Future<void> markAsDoneAndAddToCalendar(int index) async {
    if (currentUser == null) return;
    final todoId = todoList[index]['id'];
    await FirebaseFirestore.instance
        .collection('todoapp')
        .doc(currentUser!.uid)
        .collection('todos')
        .doc(todoId)
        .update({'isDone': true});
    fetchTodos();
  }

  List<Widget> get _pages {
    const Color settingsIconColor = Color(0xFF4A90E2);

    return [
      // To-Do List Page (Halaman 0)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  ...todoList.where((item) => item['isDone'] == false).map((
                    item,
                  ) {
                    int index = todoList.indexOf(item);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Checkbox(
                                value: item['isDone'],
                                onChanged: (val) {
                                  if (val == true) {
                                    markAsDoneAndAddToCalendar(index);
                                  }
                                },
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['task'],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (!item['isDone'])
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () async {
                                    final task = todoList[index];
                                    final taskId = task['id'];
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => AddEditTaskPage(
                                              isEdit: true,
                                              task: task,
                                              taskId: taskId,
                                            ),
                                      ),
                                    );
                                    if (result == true) fetchTodos();
                                  },
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder:
                                        (context) => AlertDialog(
                                          title: const Text('Konfirmasi Hapus'),
                                          content: const Text(
                                            'Apakah Anda yakin ingin menghapus tugas ini?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    false,
                                                  ),
                                              child: const Text('Batal'),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    true,
                                                  ),
                                              child: const Text('OK'),
                                            ),
                                          ],
                                        ),
                                  );
                                  if (confirm == true) {
                                    await deleteItem(index);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  if (todoList.any((item) => item['isDone'] == true))
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 2.0,
                      ),
                      child: Text(
                        'DONE',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF176B87),
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ...todoList.where((item) => item['isDone'] == true).map((
                    item,
                  ) {
                    int index = todoList.indexOf(item);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF86B6F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Checkbox(
                                value: true,
                                onChanged: (val) async {
                                  if (val == false) {
                                    await FirebaseFirestore.instance
                                        .collection('todoapp')
                                        .doc(currentUser!.uid)
                                        .collection('todos')
                                        .doc(item['id'])
                                        .update({'isDone': false});
                                    fetchTodos();
                                  }
                                },
                                checkColor: const Color(0xFF86B6F6),
                                activeColor: Colors.white,
                                side: const BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['task'],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder:
                                        (context) => AlertDialog(
                                          title: const Text('Konfirmasi Hapus'),
                                          content: const Text(
                                            'Apakah Anda yakin ingin menghapus tugas ini?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    false,
                                                  ),
                                              child: const Text('Batal'),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    true,
                                                  ),
                                              child: const Text('OK'),
                                            ),
                                          ],
                                        ),
                                  );
                                  if (confirm == true) {
                                    deleteItem(index);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      // Calendar Page (Halaman 1)
      const CalendarPage(),
      const SizedBox.shrink(),
      // Settings Page (Halaman 3)
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.brightness_6, color: settingsIconColor),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Dark/Light Mode',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Switch(value: false, onChanged: null),
                ],
              ),
              Divider(height: 32),
              Row(
                children: [
                  Icon(Icons.notifications_active, color: settingsIconColor),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Notifikasi Pengingat',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Switch(value: false, onChanged: null),
                ],
              ),
              Divider(height: 32),
              Row(
                children: [
                  Icon(Icons.sync, color: settingsIconColor),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sinkronisasi Google Calendar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Switch(value: false, onChanged: null),
                ],
              ),
              Divider(height: 32),
              Row(
                children: [
                  Icon(Icons.language, color: settingsIconColor),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bahasa (Language)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: 'ID',
                    items: [
                      DropdownMenuItem(value: 'ID', child: Text('Indonesia')),
                      DropdownMenuItem(value: 'EN', child: Text('English')),
                    ],
                    onChanged: null,
                  ),
                ],
              ),
              Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline, color: settingsIconColor),
                title: Text(
                  'Tentang Aplikasi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                subtitle: Text('Versi 1.0.0 - To Do List App'),
                onTap: null,
              ),
              Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever, color: Colors.red),
                title: Text(
                  'Reset Semua Data',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                onTap: null,
              ),
              Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.feedback_outlined,
                  color: settingsIconColor,
                ),
                title: Text(
                  'Kirim Feedback',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: null,
              ),
              Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline, color: settingsIconColor),
                title: Text(
                  'Ganti Password',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: null,
              ),
              Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.privacy_tip_outlined,
                  color: settingsIconColor,
                ),
                title: Text(
                  'Privacy Policy & Terms',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                onTap: null,
              ),
            ],
          ),
        ),
      ),
      // Profile Page (Halaman 4)
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_circle, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              displayName ?? '-',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              currentUser?.email ?? '-',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Logout', style: TextStyle(color: Colors.red)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                await _googleSignIn.signOut();
                Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF86B6F6);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'To Do List',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Color(0xFFF6F8FA),
        foregroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        color: Color(0xFFF6F8FA),
        child: SafeArea(child: _pages[_selectedIndex]),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        elevation: 8,
        color: primaryColor,
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(
                  Icons.list_alt,
                  color:
                      _selectedIndex == 0
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                  size: 28,
                ),
                onPressed: () => _onNavTapped(0),
              ),
              IconButton(
                icon: Icon(
                  Icons.calendar_today,
                  color:
                      _selectedIndex == 1
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                  size: 28,
                ),
                onPressed: () => _onNavTapped(1),
              ),
              const SizedBox(width: 56), // Space for FAB
              IconButton(
                icon: Icon(
                  Icons.settings,
                  color:
                      _selectedIndex == 3
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                  size: 28,
                ),
                onPressed: () => _onNavTapped(3),
              ),
              IconButton(
                icon: Icon(
                  Icons.person,
                  color:
                      _selectedIndex == 4
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                  size: 28,
                ),
                onPressed: () => _onNavTapped(4),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Color.fromARGB(255, 117, 163, 224),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: RawMaterialButton(
          shape: CircleBorder(),
          elevation: 0,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddEditTaskPage(isEdit: false),
              ),
            ).then((value) {
              if (value == true) fetchTodos();
            });
          },
          child: const Icon(Icons.add, color: Color(0xFFEEF5FF), size: 36),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
