import 'dart:convert';
import 'dart:io' show Directory, File;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase Init Error: $e');
    }

    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await notificationsPlugin.initialize(initSettings);

    notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  runApp(const VertragsUebersichtApp());
}

class VertragsUebersichtApp extends StatelessWidget {
  const VertragsUebersichtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vertragsübersicht',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E2022),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37),
          secondary: Color(0xFFE5C158),
          surface: Color(0xFF282A2D),
        ),
        useMaterial3: true,
      ),
      home: const GlavniEkran(),
    );
  }
}

class Ugovor {
  String id;
  String naziv;
  double cijena;
  DateTime pocetak;
  DateTime kraj;
  int trajanjeMjeseci;
  int danaPrijeIsteka;
  bool arhiviran;

  Ugovor({
    required this.id,
    required this.naziv,
    required this.cijena,
    required this.pocetak,
    required this.kraj,
    required this.trajanjeMjeseci,
    this.danaPrijeIsteka = 30,
    this.arhiviran = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'naziv': naziv,
        'cijena': cijena,
        'pocetak': pocetak.toIso8601String(),
        'kraj': kraj.toIso8601String(),
        'trajanjeMjeseci': trajanjeMjeseci,
        'danaPrijeIsteka': danaPrijeIsteka,
        'arhiviran': arhiviran,
      };

  factory Ugovor.fromMap(Map<String, dynamic> map) {
    DateTime start;
    try {
      start = DateTime.parse(map['pocetak'] ?? DateTime.now().toIso8601String());
    } catch (_) {
      start = DateTime.now();
    }

    DateTime end;
    try {
      end = DateTime.parse(map['kraj'] ?? DateTime.now().add(const Duration(days: 365)).toIso8601String());
    } catch (_) {
      end = DateTime.now().add(const Duration(days: 365));
    }

    double parsedCijena = 0.0;
    if (map['cijena'] is num) {
      parsedCijena = (map['cijena'] as num).toDouble();
    } else if (map['cijena'] is String) {
      parsedCijena = double.tryParse(map['cijena'].replaceAll(',', '.')) ?? 0.0;
    }

    return Ugovor(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      naziv: map['naziv'] ?? 'Bez naziva',
      cijena: parsedCijena,
      pocetak: start,
      kraj: end,
      trajanjeMjeseci: map['trajanjeMjeseci'] ?? 12,
      danaPrijeIsteka: map['danaPrijeIsteka'] ?? 30,
      arhiviran: map['arhiviran'] ?? false,
    );
  }

  double get ukupniTrosak => cijena * trajanjeMjeseci;

  double get progres {
    final sad = DateTime.now();
    if (sad.isBefore(pocetak)) return 0.0;
    if (sad.isAfter(kraj)) return 1.0;
    final total = kraj.difference(pocetak).inSeconds;
    final passed = sad.difference(pocetak).inSeconds;
    return total == 0 ? 1.0 : (passed / total).clamp(0.0, 1.0);
  }

  int get preostaloDana => kraj.difference(DateTime.now()).inDays;
}

class HexagonBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = const Color(0xFFD4AF37).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final paintDot = Paint()
      ..color = const Color(0xFFE5C158).withOpacity(0.35)
      ..style = PaintingStyle.fill;

    const double radius = 48.0;
    final double hexWidth = math.sqrt(3) * radius;
    final double vertDistance = 1.5 * radius;

    final int cols = (size.width / hexWidth).ceil() + 3;
    final int rows = (size.height / vertDistance).ceil() + 3;

    for (int r = -1; r < rows; r++) {
      for (int c = -1; c < cols; c++) {
        final double cx = c * hexWidth + (r % 2 == 1 ? hexWidth / 2 : 0);
        final double cy = r * vertDistance;

        final path = Path();
        for (int i = 0; i < 6; i++) {
          final double angle = math.pi / 6 + i * (math.pi / 3);
          final double x = cx + radius * math.cos(angle);
          final double y = cy + radius * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paintLine);
        canvas.drawCircle(Offset(cx, cy), 1.5, paintDot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GlavniEkran extends StatefulWidget {
  const GlavniEkran({super.key});

  @override
  State<GlavniEkran> createState() => _GlavniEkranState();
}

class _GlavniEkranState extends State<GlavniEkran> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Ugovor> _ugovori = [];
  User? _currentUser;
  bool _isSyncing = false;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _ucitajPodatke();

    if (!kIsWeb) {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        setState(() {
          _currentUser = user;
        });
        if (user != null) {
          _preuzmiIzClouda();
        }
      });
    }
  }

  Future<File> _getLokalniFajl() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ugovori_spremište.json');
  }

  Future<void> _ucitajPodatke() async {
    try {
      final file = await _getLokalniFajl();
      if (await file.exists()) {
        final String data = await file.readAsString();
        if (data.isNotEmpty) {
          final List decoded = jsonDecode(data);
          setState(() {
            _ugovori = decoded.map((e) => Ugovor.fromMap(e)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Greška pri učitavanju lokalnih podataka: $e');
    }
  }

  Future<void> _sacuvajPodatke({bool syncCloud = true}) async {
    try {
      final file = await _getLokalniFajl();
      final data = jsonEncode(_ugovori.map((e) => e.toMap()).toList());
      await file.writeAsString(data);
    } catch (e) {
      debugPrint('Greška pri snimanju lokalnih podataka: $e');
    }

    if (syncCloud && _currentUser != null && !kIsWeb) {
      await _sinhronizujNaCloud();
    }
  }

  Future<void> _sinhronizujNaCloud() async {
    if (_currentUser == null) return;
    setState(() => _isSyncing = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final userUgovoriRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('ugovori');

      final existing = await userUgovoriRef.get();
      for (var doc in existing.docs) {
        batch.delete(doc.reference);
      }

      for (var ugovor in _ugovori) {
        final docRef = userUgovoriRef.doc(ugovor.id);
        batch.set(docRef, ugovor.toMap());
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Cloud sync error: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _preuzmiIzClouda() async {
    if (_currentUser == null) return;
    setState(() => _isSyncing = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('ugovori')
          .get();

      if (snapshot.docs.isNotEmpty) {
        final cloudUgovori = snapshot.docs.map((doc) => Ugovor.fromMap(doc.data())).toList();
        
        final Map<String, Ugovor> mapaUgovora = {};
        for (var u in _ugovori) {
          mapaUgovora[u.id] = u;
        }
        for (var u in cloudUgovori) {
          mapaUgovora[u.id] = u;
        }

        setState(() {
          _ugovori = mapaUgovora.values.toList();
        });
        await _sacuvajPodatke(syncCloud: false);

        for (final u in _ugovori) {
          await _zakaziNotifikacije(u);
        }
      } else if (_ugovori.isNotEmpty) {
        await _sinhronizujNaCloud();
      }
    } catch (e) {
      debugPrint('Cloud load error: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _prijavaPrekoGooglea() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Anmeldung fehlgeschlagen: $e')),
        );
      }
    }
  }

  Future<void> _odjavaPrekoGooglea() async {
    try {
      await _googleSignIn.disconnect();
      await FirebaseAuth.instance.signOut();
      setState(() {
        _currentUser = null;
      });
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  void _prikaziKorisnickiProfil() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282A2D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD4AF37)),
        ),
        title: Text(
          _currentUser != null ? 'Konto' : 'Google Anmeldung',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE5C158)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_currentUser != null) ...[
              CircleAvatar(
                radius: 30,
                backgroundImage: _currentUser!.photoURL != null ? NetworkImage(_currentUser!.photoURL!) : null,
                child: _currentUser!.photoURL == null ? const Icon(Icons.person, size: 30) : null,
              ),
              const SizedBox(height: 12),
              Text(
                _currentUser!.displayName ?? 'Benutzer',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                _currentUser!.email ?? '',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_done, size: 18, color: Color(0xFFD4AF37)),
                  SizedBox(width: 8),
                  Text('Cloud Sync Aktiviert', style: TextStyle(color: Color(0xFFE5C158), fontSize: 13)),
                ],
              ),
            ] else ...[
              const Icon(Icons.cloud_sync_outlined, size: 48, color: Color(0xFFD4AF37)),
              const SizedBox(height: 12),
              const Text(
                'Melden Sie sich mit Google an, um Ihre Verträge sicher in der Cloud zu speichern und geräteübergreifend zu synchronisieren.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ],
        ),
        actions: [
          if (_currentUser == null)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(42),
              ),
              icon: const Icon(Icons.login),
              label: const Text('Mit Google anmelden', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(ctx);
                _prijavaPrekoGooglea();
              },
            )
          else ...[
            TextButton.icon(
              icon: const Icon(Icons.sync, color: Color(0xFFD4AF37)),
              label: const Text('Jetzt synchronisieren', style: TextStyle(color: Color(0xFFD4AF37))),
              onPressed: () {
                Navigator.pop(ctx);
                _sinhronizujNaCloud();
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text('Abmelden', style: TextStyle(color: Colors.redAccent)),
              onPressed: () {
                Navigator.pop(ctx);
                _odjavaPrekoGooglea();
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _otkaziSveNotifikacijeZaUgovor(Ugovor u) async {
    if (kIsWeb) return;
    final baseId = u.id.hashCode.abs() % 100000;
    for (int i = 0; i < 40; i++) {
      await notificationsPlugin.cancel(id: baseId + i);
    }
  }

  Future<void> _zakaziNotifikacije(Ugovor ugovor) async {
    if (kIsWeb || ugovor.arhiviran) return;

    final datumPrvogUpozorenja = ugovor.kraj.subtract(Duration(days: ugovor.danaPrijeIsteka));
    final baseId = ugovor.id.hashCode.abs() % 100000;
    final now = DateTime.now();

    DateTime zakazanoVrijeme = datumPrvogUpozorenja;
    int index = 0;

    while (zakazanoVrijeme.isBefore(ugovor.kraj) && index < 40) {
      if (zakazanoVrijeme.isAfter(now)) {
        await notificationsPlugin.zonedSchedule(
          id: baseId + index,
          title: 'Vertragskündigung: ${ugovor.naziv}',
          body: 'Haben Sie den Vertrag "${ugovor.naziv}" bereits gekündigt?',
          scheduledDate: tz.TZDateTime.from(zakazanoVrijeme, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'ugovori_channel',
              'Vertragserinnerungen',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
      zakazanoVrijeme = zakazanoVrijeme.add(const Duration(hours: 72));
      index++;
    }
  }

  DateTime _dodajMiesece(DateTime date, int months) {
    int year = date.year;
    int month = date.month + months;
    while (month > 12) {
      year++;
      month -= 12;
    }
    int day = date.day;
    int lastDayOfMonth = DateTime(year, month + 1, 0).day;
    if (day > lastDayOfMonth) {
      day = lastDayOfMonth;
    }
    return DateTime(year, month, day);
  }

  void _otvoriDijalogZaUnos({Ugovor? ugovorZaIzmjenu}) {
    final isEdit = ugovorZaIzmjenu != null;
    final nazivCtrl = TextEditingController(text: isEdit ? ugovorZaIzmjenu.naziv : '');
    final cijenaCtrl = TextEditingController(text: isEdit ? ugovorZaIzmjenu.cijena.toStringAsFixed(2) : '');
    final podsjetnikCtrl = TextEditingController(text: isEdit ? ugovorZaIzmjenu.danaPrijeIsteka.toString() : '30');

    DateTime pocetak = isEdit ? ugovorZaIzmjenu.pocetak : DateTime.now();
    int odabranoTrajanje = isEdit ? ugovorZaIzmjenu.trajanjeMjeseci : 12;
    DateTime kraj = isEdit ? ugovorZaIzmjenu.kraj : _dodajMiesece(pocetak, odabranoTrajanje);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF282A2D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Color(0xFFD4AF37), width: 1.2),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isEdit ? 'Vertrag bearbeiten' : 'Neuer Vertrag',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE5C158)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nazivCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vertragsname (z. B. Strom, Internet)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cijenaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Monatliche Kosten (€)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Startdatum:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFD4AF37))),
                  icon: const Icon(Icons.calendar_today, size: 18, color: Color(0xFFD4AF37)),
                  label: Text(
                    '${pocetak.day.toString().padLeft(2, '0')}.${pocetak.month.toString().padLeft(2, '0')}.${pocetak.year}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: pocetak,
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2050),
                    );
                    if (d != null) {
                      setModal(() {
                        pocetak = d;
                        kraj = _dodajMiesece(pocetak, odabranoTrajanje);
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                const Text('Vertragslaufzeit:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('12 Monate'),
                      selected: odabranoTrajanje == 12,
                      selectedColor: const Color(0xFFD4AF37),
                      onSelected: (val) {
                        if (val) {
                          setModal(() {
                            odabranoTrajanje = 12;
                            kraj = _dodajMiesece(pocetak, 12);
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: const Text('24 Monate'),
                      selected: odabranoTrajanje == 24,
                      selectedColor: const Color(0xFFD4AF37),
                      onSelected: (val) {
                        if (val) {
                          setModal(() {
                            odabranoTrajanje = 24;
                            kraj = _dodajMiesece(pocetak, 24);
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Enddatum: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${kraj.day.toString().padLeft(2, '0')}.${kraj.month.toString().padLeft(2, '0')}.${kraj.year}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE5C158)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: podsjetnikCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Erinnerung vor Vertragsende (Tage)',
                    hintText: '30',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    if (nazivCtrl.text.trim().isNotEmpty) {
                      final parsedCijena = double.tryParse(cijenaCtrl.text.replaceAll(',', '.')) ?? 0.0;
                      final parsedPodsjetnik = int.tryParse(podsjetnikCtrl.text.trim()) ?? 30;

                      if (isEdit) {
                        setState(() {
                          ugovorZaIzmjenu.naziv = nazivCtrl.text.trim();
                          ugovorZaIzmjenu.cijena = parsedCijena;
                          ugovorZaIzmjenu.pocetak = pocetak;
                          ugovorZaIzmjenu.kraj = kraj;
                          ugovorZaIzmjenu.trajanjeMjeseci = odabranoTrajanje;
                          ugovorZaIzmjenu.danaPrijeIsteka = parsedPodsjetnik;
                        });
                        await _zakaziNotifikacije(ugovorZaIzmjenu);
                      } else {
                        final novi = Ugovor(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          naziv: nazivCtrl.text.trim(),
                          cijena: parsedCijena,
                          pocetak: pocetak,
                          kraj: kraj,
                          trajanjeMjeseci: odabranoTrajanje,
                          danaPrijeIsteka: parsedPodsjetnik,
                        );
                        setState(() => _ugovori.add(novi));
                        await _zakaziNotifikacije(novi);
                      }

                      await _sacuvajPodatke();
                      Navigator.pop(ctx);
                    }
                  },
                  child: Text(
                    isEdit ? 'Änderungen speichern' : 'Vertrag speichern',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _prikaziDetalje(Ugovor u) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282A2D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD4AF37)),
        ),
        title: Text(u.naziv, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE5C158))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRedak('Startdatum:', '${u.pocetak.day.toString().padLeft(2, '0')}.${u.pocetak.month.toString().padLeft(2, '0')}.${u.pocetak.year}'),
            _infoRedak('Enddatum:', '${u.kraj.day.toString().padLeft(2, '0')}.${u.kraj.month.toString().padLeft(2, '0')}.${u.kraj.year}'),
            _infoRedak('Laufzeit:', '${u.trajanjeMjeseci} Monate'),
            _infoRedak('Monatliche Kosten:', '${u.cijena.toStringAsFixed(2)} €'),
            _infoRedak('Erinnerung ab:', '${u.danaPrijeIsteka} Tage vor Ende'),
            const Divider(height: 24, color: Colors.white24),
            _infoRedak(
              'Gesamtkosten:',
              '${u.ukupniTrosak.toStringAsFixed(2)} €',
              isBold: true,
              color: const Color(0xFFE5C158),
            ),
            const SizedBox(height: 10),
            Text(
              u.arhiviran
                  ? 'Vertrag ist archiviert.'
                  : (u.preostaloDana > 0 ? 'Noch ${u.preostaloDana} Tage verbleibend' : 'Vertrag ist abgelaufen!'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: u.arhiviran
                    ? Colors.grey
                    : (u.preostaloDana <= u.danaPrijeIsteka ? Colors.redAccent : const Color(0xFFE5C158)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen', style: TextStyle(color: Color(0xFFD4AF37))),
          ),
        ],
      ),
    );
  }

  Widget _infoRedak(String naslov, String vrijednost, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(naslov, style: const TextStyle(color: Colors.white70)),
          Text(
            vrijednost,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              fontSize: isBold ? 16 : 14,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup wird nur auf mobilen Geräten unterstützt.')),
      );
      return;
    }
    if (_ugovori.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Verträge zum Sichern vorhanden.')),
      );
      return;
    }
    final data = jsonEncode(_ugovori.map((e) => e.toMap()).toList());
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/vertragsuebersicht_backup.json');
    await file.writeAsString(data);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Vertragsübersicht Backup',
      text: 'Hier ist die Sicherungsdatei Ihrer Verträge.',
    );
  }

  Future<void> _importBackup() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wiederherstellung wird nur auf mobilen Geräten unterstützt.')),
      );
      return;
    }
    final result = await FilePickerPlatform.instance.pickFiles();
    if (result != null && result.isNotEmpty && result.first.path != null) {
      try {
        final file = File(result.first.path!);
        final content = await file.readAsString();
        final List decoded = jsonDecode(content);
        final loaded = decoded.map((e) => Ugovor.fromMap(e)).toList();

        setState(() {
          _ugovori = loaded;
        });
        await _sacuvajPodatke();

        for (final u in _ugovori) {
          await _zakaziNotifikacije(u);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loaded.length} Verträge erfolgreich wiederhergestellt!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Wiederherstellen der Datei.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final aktivni = _ugovori.where((u) => !u.arhiviran).toList();
    final arhivirani = _ugovori.where((u) => u.arhiviran).toList();

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: HexagonBackgroundPainter(),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E2022).withOpacity(0.9),
            elevation: 0,
            leading: IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
                    )
                  : (_currentUser != null && _currentUser!.photoURL != null
                      ? CircleAvatar(
                          radius: 14,
                          backgroundImage: NetworkImage(_currentUser!.photoURL!),
                        )
                      : Icon(
                          _currentUser != null ? Icons.account_circle : Icons.account_circle_outlined,
                          color: const Color(0xFFD4AF37),
                        )),
              onPressed: _prikaziKorisnickiProfil,
            ),
            title: const Text(
              'Vertragsübersicht',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE5C158)),
            ),
            centerTitle: true,
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.settings_backup_restore, color: Color(0xFFD4AF37)),
                onSelected: (val) {
                  if (val == 'export') _exportBackup();
                  if (val == 'import') _importBackup();
                  if (val == 'sync') _sinhronizujNaCloud();
                },
                itemBuilder: (context) => [
                  if (_currentUser != null)
                    const PopupMenuItem(
                      value: 'sync',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_upload, size: 18, color: Color(0xFFD4AF37)),
                          SizedBox(width: 8),
                          Text('Jetzt mit Cloud synchronisieren'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.upload, size: 18, color: Color(0xFFD4AF37)),
                        SizedBox(width: 8),
                        Text('Backup erstellen (Drive/Share)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'import',
                    child: Row(
                      children: [
                        Icon(Icons.download, size: 18, color: Color(0xFFD4AF37)),
                        SizedBox(width: 8),
                        Text('Backup wiederherstellen'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFD4AF37),
              labelColor: const Color(0xFFE5C158),
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: 'Aktiv (${aktivni.length})'),
                Tab(text: 'Archiv (${arhivirani.length})'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _listaPrikaz(aktivni, isArchiv: false),
              _listaPrikaz(arhivirani, isArchiv: true),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: Colors.black,
            onPressed: () => _otvoriDijalogZaUnos(),
            child: const Icon(Icons.add, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _listaPrikaz(List<Ugovor> lista, {required bool isArchiv}) {
    if (lista.isEmpty) {
      return Center(
        child: Text(
          isArchiv
              ? 'Keine archivierten Verträge vorhanden.'
              : 'Keine aktiven Verträge vorhanden.\nTippe auf das +, um einen Vertrag hinzuzufügen.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: lista.length,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemBuilder: (ctx, i) {
        final u = lista[i];
        final istice = u.preostaloDana <= u.danaPrijeIsteka;

        return Card(
          color: const Color(0xFF282A2D).withOpacity(0.92),
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isArchiv ? Colors.white12 : const Color(0xFFD4AF37).withOpacity(0.4),
              width: 1.1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _prikaziDetalje(u),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.naziv,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isArchiv ? Colors.grey : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: u.progres,
                            minHeight: 6,
                            backgroundColor: Colors.white10,
                            color: isArchiv
                                ? Colors.grey
                                : (istice ? Colors.redAccent : const Color(0xFFD4AF37)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isArchiv
                                  ? 'Archiviert'
                                  : (u.preostaloDana > 0 ? 'Noch ${u.preostaloDana} Tage' : 'Abgelaufen!'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isArchiv
                                    ? Colors.grey
                                    : (istice ? Colors.redAccent : const Color(0xFFE5C158)),
                              ),
                            ),
                            Text(
                              '${u.cijena.toStringAsFixed(2)} € / Mt.',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                    onSelected: (val) async {
                      if (val == 'edit') {
                        _otvoriDijalogZaUnos(ugovorZaIzmjenu: u);
                      } else if (val == 'archive') {
                        setState(() {
                          u.arhiviran = !u.arhiviran;
                        });
                        if (u.arhiviran) {
                          await _otkaziSveNotifikacijeZaUgovor(u);
                        } else {
                          await _zakaziNotifikacije(u);
                        }
                        await _sacuvajPodatke();
                      } else if (val == 'delete') {
                        setState(() => _ugovori.remove(u));
                        await _otkaziSveNotifikacijeZaUgovor(u);
                        await _sacuvajPodatke();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18, color: Color(0xFFD4AF37)),
                            SizedBox(width: 8),
                            Text('Bearbeiten'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Row(
                          children: [
                            Icon(
                              u.arhiviran ? Icons.unarchive : Icons.archive,
                              size: 18,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 8),
                            Text(u.arhiviran ? 'Wiederherstellen' : 'Archivieren'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('Löschen'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}