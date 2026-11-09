// ===========================================================================
// 61. EL CAMINO DEL DÍA (solo en la app instalada: Android y iPhone)
//
// En el Dojo, el banner muestra un mapa en vivo de donde estás y lleva la
// cuenta de tus pasos, kilómetros y calorías del día.
// - Pasos: el sensor de pasos del teléfono. Cuenta aunque la app esté
//   cerrada; si el teléfono no tiene sensor (o no dio permiso), se estiman
//   con el GPS mientras la app está abierta.
// - Ubicación: solo mientras la app está abierta y el banner o la pantalla
//   del camino están a la vista. Nunca en segundo plano.
// - Nada sale del teléfono: la ubicación, el recorrido y los pasos no se
//   guardan en la cuenta ni se ven en el Clan.
// - El mapa son teselas vectoriales de OpenFreeMap (gratis, sin llave ni
//   cuenta, uso comercial permitido) pintadas con los colores del tema.
//
// La web no compila este archivo: usa camino_web.dart y el Dojo muestra la
// tarjeta CaminoEnWeb, que invita a instalar la app.
// ===========================================================================

import 'dart:async';
import 'dart:convert' as convert;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, FilteringTextInputFormatter, TextInputFormatter;
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:pedometer/pedometer.dart' as podo;
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart' show SharedPreferences;
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

import 'main.dart';

/// El banner del Dojo (en la web, camino_web.dart devuelve un espacio vacío).
Widget bannerCamino({required double vitalidad, required bool entrenoHoy}) =>
    CaminoDelDia(vitalidad: vitalidad, entrenoHoy: entrenoHoy);

// ---------------------------------------------------------------------------
// 61.1 EL CAMINANTE: pasos, ubicación y cifras del día
// ---------------------------------------------------------------------------

enum EstadoCamino { apagado, activo, sinPermiso, bloqueado, gpsApagado }

class Caminante extends ChangeNotifier with WidgetsBindingObserver {
  Caminante._();
  static final Caminante instancia = Caminante._();

  static const String _kActivado = 'camino_activado';
  static const String _kDia = 'camino_dia';
  static const String _kBase = 'camino_base';
  static const String _kUltimo = 'camino_ultimo';
  static const String _kAcum = 'camino_acum';
  static const String _kHoy = 'camino_hoy';
  static const String _kHistorial = 'camino_historial';
  static const String _kDiaGps = 'camino_dia_gps';
  static const String _kMetros = 'camino_metros';
  static const String _kEstatura = 'camino_estatura';
  static const String _kMeta = 'camino_meta';

  SharedPreferences? _prefs;
  Future<void>? _carga;

  /// La persona activó el camino (vio el aviso y dijo que sí).
  bool activado = false;
  EstadoCamino estado = EstadoCamino.apagado;

  // Pasos del sensor. El sensor cuenta desde que se encendió el teléfono:
  // `_base` es la lectura con la que empezó el día y `_acum` lo que se
  // contó hoy antes de un reinicio.
  bool sensorPasos = true;
  bool permisoPasos = true;
  int _pasosSensor = 0;
  String _dia = '';
  int? _base;
  int? _ultimo;
  int _acum = 0;
  Map<String, int> historial = <String, int>{};

  // Ubicación: solo en memoria.
  LatLng? posicion;
  double? rumbo;
  double velocidad = 0;
  final List<LatLng> rastro = <LatLng>[];
  double metrosGps = 0;
  String _diaGps = '';
  LatLng? _previa;
  DateTime? _horaPrevia;

  int? estaturaCm;
  int meta = 8000;

  int _usuarios = 0;
  bool _primerPlano = true;
  bool _buscandoGps = false;
  StreamSubscription<podo.StepCount>? _subPasos;
  StreamSubscription<geo.Position>? _subGps;
  Timer? _guardado;

  static String fecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String get hoy => fecha(DateTime.now());

  bool get gpsEnVivo => _subGps != null && posicion != null;

  /// Sin sensor de pasos (o sin permiso), los pasos se estiman con el GPS.
  bool get pasosConGps => !sensorPasos || !permisoPasos;

  int get pasosHoy {
    if (!pasosConGps) return _dia == hoy ? _pasosSensor : 0;
    if (_diaGps != hoy) return 0;
    return (metrosGps / zancada).round();
  }

  int pasosDe(String dia) => dia == hoy ? pasosHoy : (historial[dia] ?? 0);

  bool get _mujer => SesionTemplo.instancia.actual?.genero == 'mujer';

  /// La estatura guardada o, si no hay, la media según el género.
  int get estaturaUsada => estaturaCm ?? (_mujer ? 160 : 172);

  /// Largo del paso en metros (estatura × 0,415 en hombres, × 0,413 en mujeres).
  double get zancada => estaturaUsada / 100 * (_mujer ? 0.413 : 0.415);

  double get km => pasosHoy * zancada / 1000;

  /// Calorías activas aproximadas: unas 0,5 kcal por kilo de peso y por
  /// kilómetro caminado (ecuación de marcha del ACSM, sin el gasto en reposo).
  double get kcal => km * CargaCorporal.kg * 0.5;

  double get progreso => meta <= 0 ? 0 : (pasosHoy / meta).clamp(0.0, 1.0);

  Future<void> cargar() => _carga ??= _cargar();

  Future<void> _cargar() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _prefs = p;
      activado = p.getBool(_kActivado) ?? false;
      _dia = p.getString(_kDia) ?? '';
      _base = p.getInt(_kBase);
      _ultimo = p.getInt(_kUltimo);
      _acum = p.getInt(_kAcum) ?? 0;
      _pasosSensor = p.getInt(_kHoy) ?? 0;
      estaturaCm = p.getInt(_kEstatura);
      meta = p.getInt(_kMeta) ?? 8000;
      if (p.getString(_kDiaGps) == hoy) {
        _diaGps = hoy;
        metrosGps = p.getDouble(_kMetros) ?? 0;
      }
      final String? h = p.getString(_kHistorial);
      if (h != null) {
        final Object? m = convert.jsonDecode(h);
        if (m is Map) {
          historial = <String, int>{
            for (final MapEntry<dynamic, dynamic> e in m.entries)
              if (e.value is num) e.key.toString(): (e.value as num).toInt(),
          };
        }
      }
    } catch (_) {
      // Sin almacenamiento: el camino funciona igual, solo no recuerda.
    }
    if (vistaPrueba) activado = true;
    notifyListeners();
    unawaited(_arrancar());
  }

  /// Un banner o la pantalla del camino se ve: se enciende el GPS.
  void entrar() {
    _usuarios++;
    unawaited(cargar().then((_) => _arrancar()));
  }

  /// Ya no se ve: el GPS se apaga cuando no queda nadie mirando.
  void salir() {
    if (_usuarios > 0) _usuarios--;
    if (_usuarios == 0) _detenerGps();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      if (!_primerPlano) {
        _primerPlano = true;
        unawaited(_arrancar());
      }
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden || s == AppLifecycleState.detached) {
      _primerPlano = false;
      _detenerGps();
      _detenerPasos();
      _guardarYa();
    }
  }

  /// Tras el aviso: pide los permisos del teléfono y arranca.
  Future<void> activar() async {
    await cargar();
    activado = true;
    try {
      await _prefs?.setBool(_kActivado, true);
    } catch (_) {}
    notifyListeners();
    await _arrancar(pedir: true);
  }

  Future<void> pedirUbicacion() => _arrancar(pedir: true);

  Future<void> _arrancar({bool pedir = false}) async {
    if (!activado || !_primerPlano) return;
    await _revisarPermisoPasos(pedir: pedir);
    _iniciarPasos();
    if (_usuarios > 0) await _iniciarGps(pedir: pedir);
  }

  Future<void> _revisarPermisoPasos({required bool pedir}) async {
    // En Android 10 o más, el sensor de pasos necesita «Actividad física».
    // En iPhone lo pide el propio sistema la primera vez.
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      ph.PermissionStatus s = await ph.Permission.activityRecognition.status;
      if (!s.isGranted && pedir) s = await ph.Permission.activityRecognition.request();
      final bool antes = permisoPasos;
      permisoPasos = s.isGranted;
      if (antes != permisoPasos) notifyListeners();
    } catch (_) {
      // Si no se puede saber, se intenta igual con el sensor.
    }
  }

  void _iniciarPasos() {
    if (_subPasos != null || !permisoPasos) return;
    try {
      _subPasos = podo.Pedometer.stepCountStream.listen(
        (podo.StepCount e) => _alContar(e.steps),
        onError: (Object _) {
          // El teléfono no tiene sensor de pasos: se cuentan con el GPS.
          _subPasos = null;
          sensorPasos = false;
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (_) {
      sensorPasos = false;
    }
  }

  void _detenerPasos() {
    _subPasos?.cancel();
    _subPasos = null;
  }

  void _alContar(int r) {
    if (r < 0) return;
    final DateTime ahora = DateTime.now();
    final String dia = fecha(ahora);
    if (_dia != dia) {
      if (_dia.isNotEmpty) historial[_dia] = _pasosSensor;
      // Si la última lectura fue ayer, lo caminado desde entonces cuenta hoy.
      final int? u = _ultimo;
      final bool seguido = _dia == fecha(ahora.subtract(const Duration(days: 1))) && u != null && u <= r;
      _dia = dia;
      _acum = 0;
      _base = seguido ? u : r;
    } else if (_ultimo != null && r < _ultimo!) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // El contador volvió a cero: el teléfono se reinició hoy.
        _acum += math.max(0, _ultimo! - (_base ?? _ultimo!));
        _base = 0;
      } else {
        // iPhone: la ventana del sensor se movió. Se conserva lo de hoy.
        _acum = _pasosSensor;
        _base = r;
      }
    }
    _base ??= r;
    _ultimo = r;
    _pasosSensor = _acum + math.max(0, r - _base!);
    historial[dia] = _pasosSensor;
    sensorPasos = true;
    _guardarPronto();
    notifyListeners();
  }

  Future<void> _iniciarGps({bool pedir = false}) async {
    if (_subGps != null || _buscandoGps) return;
    _buscandoGps = true;
    try {
      bool servicio = false;
      try {
        servicio = await geo.Geolocator.isLocationServiceEnabled();
      } catch (_) {}
      if (!servicio) {
        _poner(EstadoCamino.gpsApagado);
        return;
      }
      geo.LocationPermission permiso = geo.LocationPermission.denied;
      try {
        permiso = await geo.Geolocator.checkPermission();
        if (permiso == geo.LocationPermission.denied && pedir) {
          permiso = await geo.Geolocator.requestPermission();
        }
      } catch (_) {}
      if (permiso == geo.LocationPermission.deniedForever) {
        _poner(EstadoCamino.bloqueado);
        return;
      }
      if (permiso != geo.LocationPermission.whileInUse && permiso != geo.LocationPermission.always) {
        _poner(EstadoCamino.sinPermiso);
        return;
      }
      if (!_primerPlano || _usuarios == 0) return;
      _poner(EstadoCamino.activo);
      if (posicion == null) {
        try {
          final geo.Position? u = await geo.Geolocator.getLastKnownPosition();
          if (u != null && posicion == null) _alMoverse(u, contar: false);
        } catch (_) {}
      }
      if (!_primerPlano || _usuarios == 0) return;
      final geo.LocationSettings ajustes = defaultTargetPlatform == TargetPlatform.iOS
          ? geo.AppleSettings(
              accuracy: geo.LocationAccuracy.best,
              distanceFilter: 4,
              activityType: geo.ActivityType.fitness,
              pauseLocationUpdatesAutomatically: true,
              // Solo con la app abierta: nunca en segundo plano.
              allowBackgroundLocationUpdates: false,
            )
          : geo.AndroidSettings(
              accuracy: geo.LocationAccuracy.high,
              distanceFilter: 4,
              intervalDuration: const Duration(seconds: 3),
            );
      _subGps = geo.Geolocator.getPositionStream(locationSettings: ajustes).listen(
        _alMoverse,
        onError: (Object e) {
          _detenerGps();
          _poner(e is geo.LocationServiceDisabledException ? EstadoCamino.gpsApagado : EstadoCamino.sinPermiso);
        },
      );
      notifyListeners();
    } finally {
      _buscandoGps = false;
    }
  }

  void _detenerGps() {
    _subGps?.cancel();
    _subGps = null;
  }

  void _alMoverse(geo.Position p, {bool contar = true}) {
    if (!p.latitude.isFinite || !p.longitude.isFinite) return;
    final LatLng aqui = LatLng(p.latitude, p.longitude);
    final String dia = hoy;
    if (_diaGps != dia) {
      if (_diaGps.isNotEmpty && pasosConGps) historial[_diaGps] = (metrosGps / zancada).round();
      _diaGps = dia;
      metrosGps = 0;
      rastro.clear();
      _previa = null;
    }
    if (contar && p.accuracy <= 35) {
      final LatLng? antes = _previa;
      if (antes == null) {
        _previa = aqui;
      } else {
        final double d = geo.Geolocator.distanceBetween(antes.latitude, antes.longitude, aqui.latitude, aqui.longitude);
        if (d > 120) {
          _previa = aqui; // Salto del GPS: no se suma.
        } else if (d >= 5) {
          metrosGps += d;
          _previa = aqui;
        }
      }
      if (rastro.isEmpty ||
          geo.Geolocator.distanceBetween(rastro.last.latitude, rastro.last.longitude, aqui.latitude, aqui.longitude) >= 5) {
        rastro.add(aqui);
        if (rastro.length > 1500) rastro.removeRange(0, rastro.length - 1500);
      }
      _guardarPronto();
    }
    // Velocidad y rumbo: los del GPS; si el teléfono no los da, se sacan de
    // la posición anterior.
    final LatLng? antes = posicion;
    final DateTime? horaAntes = _horaPrevia;
    double v = p.speed.isFinite && p.speed > 0 ? p.speed : 0;
    double? r = v > 0 && p.heading.isFinite && p.heading >= 0 ? p.heading : null;
    if (v <= 0 && antes != null && horaAntes != null) {
      final double seg = p.timestamp.difference(horaAntes).inMilliseconds / 1000;
      if (seg >= 1 && seg <= 30) {
        final double d = geo.Geolocator.distanceBetween(antes.latitude, antes.longitude, aqui.latitude, aqui.longitude);
        v = d / seg;
        if (d >= 3) r = _rumboEntre(antes, aqui);
      }
    }
    _horaPrevia = p.timestamp;
    posicion = aqui;
    velocidad = v;
    if (r != null && velocidad > 0.6) {
      rumbo = r;
    } else if (velocidad < 0.3) {
      rumbo = null;
    }
    estado = EstadoCamino.activo;
    notifyListeners();
  }

  /// Rumbo de a hacia b, en grados desde el norte.
  static double _rumboEntre(LatLng a, LatLng b) {
    final double f1 = a.latitude * math.pi / 180;
    final double f2 = b.latitude * math.pi / 180;
    final double dl = (b.longitude - a.longitude) * math.pi / 180;
    final double y = math.sin(dl) * math.cos(f2);
    final double x = math.cos(f1) * math.sin(f2) - math.sin(f1) * math.cos(f2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void _poner(EstadoCamino e) {
    if (estado == e) return;
    estado = e;
    notifyListeners();
  }

  Future<void> ponerEstatura(int? cm) async {
    estaturaCm = cm;
    notifyListeners();
    try {
      if (cm == null) {
        await _prefs?.remove(_kEstatura);
      } else {
        await _prefs?.setInt(_kEstatura, cm);
      }
    } catch (_) {}
  }

  Future<void> ponerMeta(int pasos) async {
    meta = pasos;
    notifyListeners();
    try {
      await _prefs?.setInt(_kMeta, pasos);
    } catch (_) {}
  }

  void _guardarPronto() {
    _guardado ??= Timer(const Duration(seconds: 4), _guardarYa);
  }

  void _guardarYa() {
    _guardado?.cancel();
    _guardado = null;
    final SharedPreferences? p = _prefs;
    if (p == null) return;
    if (historial.length > 35) {
      final List<String> dias = historial.keys.toList()..sort();
      for (final String d in dias.take(dias.length - 35)) {
        historial.remove(d);
      }
    }
    try {
      unawaited(p.setString(_kDia, _dia));
      if (_base != null) unawaited(p.setInt(_kBase, _base!));
      if (_ultimo != null) unawaited(p.setInt(_kUltimo, _ultimo!));
      unawaited(p.setInt(_kAcum, _acum));
      unawaited(p.setInt(_kHoy, _pasosSensor));
      unawaited(p.setString(_kDiaGps, _diaGps));
      unawaited(p.setDouble(_kMetros, metrosGps));
      unawaited(p.setString(_kHistorial, convert.jsonEncode(historial)));
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// 61.2 ESTILO DEL MAPA: OpenFreeMap con los colores del tema
// ---------------------------------------------------------------------------

class EstiloCamino {
  const EstiloCamino._();

  static Future<vt.Style?>? _fuentes;
  static final Map<String, vt.Theme> _temas = <String, vt.Theme>{};

  /// Lo que pide la licencia de los datos del mapa.
  static const String atribucion = '© OpenMapTiles © OpenStreetMap';

  /// Fuentes de las teselas (lee el TileJSON de OpenFreeMap una vez).
  static Future<vt.Style?> fuentes() => _fuentes ??= _leer();

  static Future<vt.Style?> _leer() async {
    try {
      return await const vt.StyleReader(uri: 'asset://assets/mapa/camino.json').read();
    } catch (_) {
      _fuentes = null; // Sin conexión: se intenta de nuevo la próxima vez.
      return null;
    }
  }

  static vt.Theme tema() {
    final PaletaTemplo p = TemaTemplo.paleta;
    return _temas.putIfAbsent(p.id, () => const vt.ThemeReader().read(_estilo(p.claro), id: 'camino-${p.id}-1'));
  }

  static Color fondo() => TemaTemplo.paleta.claro
      ? Color.lerp(TempleColors.negro, Colors.white, 0.35)!
      : Color.lerp(TempleColors.negro, TempleColors.grafito, 0.6)!;

  static String _hex(Color c) {
    String dos(double v) => math.min(255, math.max(0, (v * 255).round())).toRadixString(16).padLeft(2, '0');
    return '#${dos(c.r)}${dos(c.g)}${dos(c.b)}';
  }

  static Map<String, Object?> _estilo(bool claro) {
    final Color tierra = fondo();
    final Color agua = Color.lerp(tierra, TempleColors.violeta, claro ? 0.22 : 0.28)!;
    final Color verde = Color.lerp(tierra, TempleColors.violeta, claro ? 0.07 : 0.10)!;
    final Color edificio = Color.lerp(tierra, TempleColors.bordeVivo, claro ? 0.30 : 0.40)!;
    final Color menor = claro ? Colors.white : Color.lerp(tierra, TempleColors.bordeVivo, 0.75)!;
    final Color borde = Color.lerp(tierra, TempleColors.bordeVivo, 0.6)!;
    final Color mayor = claro
        ? Color.lerp(Colors.white, TempleColors.violetaClaro, 0.35)!
        : Color.lerp(TempleColors.bordeVivo, TempleColors.violeta, 0.45)!;
    final Color autopista = Color.lerp(TempleColors.bordeVivo, TempleColors.violeta, claro ? 0.55 : 0.75)!;

    List<Object> ancho(List<num> pares) => <Object>['interpolate', <Object>['exponential', 1.5], <Object>['zoom'], ...pares];
    List<Object> clase(List<String> c) => <Object>['match', <Object>['get', 'class'], c, true, false];
    Map<String, Object?> linea(String id, List<String> clases, Color color, List<num> anchos, {int? minzoom}) =>
        <String, Object?>{
          'id': id,
          'type': 'line',
          'source': 'openmaptiles',
          'source-layer': 'transportation',
          if (minzoom != null) 'minzoom': minzoom,
          'filter': clase(clases),
          'layout': <String, Object?>{'line-cap': 'round', 'line-join': 'round'},
          'paint': <String, Object?>{'line-color': _hex(color), 'line-width': ancho(anchos)},
        };

    const List<String> calles = <String>['minor', 'service'];
    const List<String> avenidas = <String>['tertiary', 'secondary', 'primary', 'trunk'];
    final List<Map<String, Object?>> capas = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'fondo',
        'type': 'background',
        'paint': <String, Object?>{'background-color': _hex(tierra)},
      },
      <String, Object?>{
        'id': 'verde',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landcover',
        'filter': clase(<String>['grass', 'wood', 'wetland']),
        'paint': <String, Object?>{'fill-color': _hex(verde)},
      },
      <String, Object?>{
        'id': 'parques',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'park',
        'paint': <String, Object?>{'fill-color': _hex(verde)},
      },
      <String, Object?>{
        'id': 'agua',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'water',
        'paint': <String, Object?>{'fill-color': _hex(agua)},
      },
      <String, Object?>{
        'id': 'rios',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'waterway',
        'paint': <String, Object?>{'line-color': _hex(agua), 'line-width': ancho(<num>[10, 0.6, 16, 3])},
      },
      <String, Object?>{
        'id': 'edificios',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'building',
        'minzoom': 14,
        'paint': <String, Object?>{'fill-color': _hex(edificio), 'fill-opacity': 0.6},
      },
      <String, Object?>{
        'id': 'senderos',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'minzoom': 14,
        'filter': clase(<String>['path', 'track']),
        'layout': <String, Object?>{'line-cap': 'round'},
        'paint': <String, Object?>{
          'line-color': _hex(claro ? borde : menor),
          'line-opacity': 0.75,
          'line-width': ancho(<num>[14, 0.6, 18, 1.8]),
          'line-dasharray': <num>[1.5, 1.5],
        },
      },
      if (claro) linea('calles_borde', calles, borde, <num>[13, 1.2, 16, 6, 18, 15], minzoom: 13),
      linea('calles', calles, menor, <num>[12, 0.4, 14, 1.4, 16, 4.5, 18, 12]),
      if (claro) linea('avenidas_borde', avenidas, borde, <num>[10, 1.2, 14, 3.6, 16, 8.5, 18, 19]),
      linea('avenidas', avenidas, mayor, <num>[10, 0.7, 14, 2.4, 16, 6.5, 18, 16]),
      linea('autopistas', <String>['motorway'], autopista, <num>[8, 0.8, 14, 3, 16, 8, 18, 20]),
      <String, Object?>{
        'id': 'nombres_calles',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'transportation_name',
        'minzoom': 15,
        'layout': <String, Object?>{
          'symbol-placement': 'line',
          'text-field': <Object>['get', 'name'],
          'text-size': 11,
          'text-font': <String>['Noto Sans Regular'],
        },
        'paint': <String, Object?>{
          'text-color': _hex(TempleColors.textoSuave),
          'text-halo-color': _hex(tierra),
          'text-halo-width': 1.4,
        },
      },
      <String, Object?>{
        'id': 'barrios',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'filter': clase(<String>['suburb', 'neighbourhood', 'quarter', 'village', 'town', 'city']),
        'layout': <String, Object?>{
          'text-field': <Object>['get', 'name'],
          'text-size': 11.5,
          'text-letter-spacing': 0.12,
          'text-transform': 'uppercase',
          'text-max-width': 8,
          'text-font': <String>['Noto Sans Regular'],
        },
        'paint': <String, Object?>{
          'text-color': _hex(TempleColors.textoTenue),
          'text-halo-color': _hex(tierra),
          'text-halo-width': 1.2,
        },
      },
    ];
    return <String, Object?>{
      'version': 8,
      'name': 'Camino del templo',
      'sources': <String, Object?>{
        'openmaptiles': <String, Object?>{'type': 'vector'},
      },
      'layers': capas,
    };
  }
}

// ---------------------------------------------------------------------------
// 61.3 EL MAPA: sigue a la persona mientras camina
// ---------------------------------------------------------------------------

class MapaCamino extends StatefulWidget {
  const MapaCamino({super.key, required this.interactivo, this.zoom = 16.3});

  /// En el banner el mapa no se toca (la lista del Dojo sigue deslizando);
  /// en la pantalla del camino se puede mover y hacer zoom.
  final bool interactivo;
  final double zoom;

  @override
  State<MapaCamino> createState() => _MapaCaminoState();
}

class _MapaCaminoState extends State<MapaCamino> with SingleTickerProviderStateMixin {
  final fm.MapController _mapa = fm.MapController();
  late final AnimationController _vuelo =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..addListener(_volar);
  LatLng? _desde;
  LatLng? _hacia;
  LatLng? _vista;
  bool _listo = false;
  bool _seguir = true;
  vt.Style? _fuentes;

  @override
  void initState() {
    super.initState();
    Caminante.instancia.addListener(_alCambiar);
    EstiloCamino.fuentes().then((vt.Style? s) {
      if (mounted && s != null) setState(() => _fuentes = s);
    });
  }

  @override
  void dispose() {
    Caminante.instancia.removeListener(_alCambiar);
    _vuelo.dispose();
    _mapa.dispose();
    super.dispose();
  }

  void _alCambiar() {
    final LatLng? p = Caminante.instancia.posicion;
    if (p != null && _listo && _seguir && p != _vista) _irA(p);
    if (mounted) setState(() {});
  }

  void _irA(LatLng p) {
    _vista = p;
    final LatLng desde = _mapa.camera.center;
    final double d = geo.Geolocator.distanceBetween(desde.latitude, desde.longitude, p.latitude, p.longitude);
    if (d > 1500 || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _vuelo.stop();
      _mapa.move(p, _mapa.camera.zoom);
      return;
    }
    _desde = desde;
    _hacia = p;
    _vuelo.forward(from: 0);
  }

  void _volar() {
    final LatLng? a = _desde;
    final LatLng? b = _hacia;
    if (a == null || b == null || !_listo) return;
    final double t = Curves.easeOutCubic.transform(_vuelo.value);
    _mapa.move(
      LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t),
      _mapa.camera.zoom,
    );
  }

  void _centrar() {
    HapticFeedback.selectionClick();
    setState(() => _seguir = true);
    final LatLng? p = Caminante.instancia.posicion;
    if (p != null && _listo) _irA(p);
  }

  @override
  Widget build(BuildContext context) {
    final Caminante c = Caminante.instancia;
    final LatLng? aqui = c.posicion;
    final vt.Style? f = _fuentes;
    final Widget mapa = fm.FlutterMap(
      mapController: _mapa,
      options: fm.MapOptions(
        initialCenter: aqui ?? const LatLng(4.6097, -74.0817),
        initialZoom: widget.zoom,
        minZoom: 11,
        maxZoom: 18.5,
        backgroundColor: EstiloCamino.fondo(),
        interactionOptions: fm.InteractionOptions(
          flags: widget.interactivo ? fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate : fm.InteractiveFlag.none,
        ),
        onMapReady: () {
          _listo = true;
          final LatLng? p = Caminante.instancia.posicion;
          if (p != null) {
            _vista = p;
            _mapa.move(p, _mapa.camera.zoom);
          }
        },
        onPositionChanged: (fm.MapCamera camara, bool gesto) {
          if (gesto && widget.interactivo && _seguir) setState(() => _seguir = false);
        },
      ),
      children: <Widget>[
        if (f != null)
          vt.VectorTileLayer(
            theme: EstiloCamino.tema(),
            tileProviders: f.providers,
            concurrency: 2,
            memoryCacheMaxBytes: 16 * 1024 * 1024,
            diskCacheMaximumSizeInBytes: 40 * 1024 * 1024,
          ),
        if (c.rastro.length >= 2)
          fm.PolylineLayer(
            polylines: <fm.Polyline>[
              fm.Polyline(
                points: List<LatLng>.of(c.rastro),
                strokeWidth: 4.5,
                color: TempleColors.violetaClaro.withValues(alpha: 0.9),
                borderStrokeWidth: 2.5,
                borderColor: TempleColors.negro.withValues(alpha: 0.4),
              ),
            ],
          ),
        if (aqui != null)
          fm.MarkerLayer(
            markers: <fm.Marker>[
              fm.Marker(point: aqui, width: 72, height: 72, child: PuntoCaminante(rumbo: c.rumbo)),
            ],
          ),
      ],
    );
    if (!widget.interactivo) return mapa;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: mapa),
        if (!_seguir)
          Positioned(
            right: 14,
            bottom: 14,
            child: _BotonRedondo(icono: Icons.my_location_rounded, etiqueta: 'Volver a mi ubicación', onTap: _centrar),
          ),
        const Positioned(left: 10, bottom: 10, child: _Atribucion()),
      ],
    );
  }
}

/// La persona en el mapa: punto violeta con pulso y, al caminar, hacia dónde va.
class PuntoCaminante extends StatefulWidget {
  const PuntoCaminante({super.key, this.rumbo});
  final double? rumbo;

  @override
  State<PuntoCaminante> createState() => _PuntoCaminanteState();
}

class _PuntoCaminanteState extends State<PuntoCaminante> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
      _c.value = 0.35;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, _) => CustomPaint(
          painter: _PuntoPainter(
            t: _c.value,
            rumbo: widget.rumbo,
            acento: TempleColors.violeta,
            brillo: TempleColors.violetaClaro,
            aro: TemaTemplo.esClaro ? Colors.white : TempleColors.blancoLuna,
          ),
        ),
      ),
    );
  }
}

class _PuntoPainter extends CustomPainter {
  const _PuntoPainter({
    required this.t,
    required this.rumbo,
    required this.acento,
    required this.brillo,
    required this.aro,
  });

  final double t;
  final double? rumbo;
  final Color acento;
  final Color brillo;
  final Color aro;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    canvas.drawCircle(c, 9 + 22 * t, Paint()..color = brillo.withValues(alpha: 0.38 * (1 - t)));
    final double? r = rumbo;
    if (r != null) {
      final double a = (r - 90) * math.pi / 180;
      final Rect caja = Rect.fromCircle(center: c, radius: 30);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..arcTo(caja, a - 0.45, 0.9, false)
          ..close(),
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[acento.withValues(alpha: 0.6), acento.withValues(alpha: 0)],
          ).createShader(caja),
      );
    }
    canvas.drawCircle(
      c,
      12,
      Paint()
        ..color = acento.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(c, 8.5, Paint()..color = aro);
    canvas.drawCircle(c, 6, Paint()..color = acento);
  }

  @override
  bool shouldRepaint(_PuntoPainter o) => o.t != t || o.rumbo != rumbo || o.acento != acento;
}

// ---------------------------------------------------------------------------
// 61.4 EL BANNER DEL DOJO
// ---------------------------------------------------------------------------

/// Enciende el GPS mientras el widget se ve (pestaña activa y ruta visible)
/// y lo apaga cuando se tapa o se va.
mixin _PresenciaCamino<T extends StatefulWidget> on State<T> {
  ValueListenable<TickerModeData>? _modo;
  bool _dentro = false;

  void _alCambiarCamino() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    Caminante.instancia.addListener(_alCambiarCamino);
    unawaited(Caminante.instancia.cargar());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ValueListenable<TickerModeData> nuevo = TickerMode.getValuesNotifier(context);
    if (!identical(nuevo, _modo)) {
      _modo?.removeListener(_alModo);
      nuevo.addListener(_alModo);
      _modo = nuevo;
    }
    _alModo();
  }

  void _alModo() {
    final bool visible = _modo?.value.enabled ?? true;
    if (visible && !_dentro) {
      _dentro = true;
      Caminante.instancia.entrar();
    } else if (!visible && _dentro) {
      _dentro = false;
      Caminante.instancia.salir();
    }
  }

  @override
  void dispose() {
    _modo?.removeListener(_alModo);
    Caminante.instancia.removeListener(_alCambiarCamino);
    if (_dentro) Caminante.instancia.salir();
    super.dispose();
  }
}

class CaminoDelDia extends StatefulWidget {
  const CaminoDelDia({
    super.key,
    required this.vitalidad,
    required this.entrenoHoy,
    this.altura = 268,
  });

  final double vitalidad;
  final bool entrenoHoy;
  final double altura;

  @override
  State<CaminoDelDia> createState() => _CaminoDelDiaState();
}

class _CaminoDelDiaState extends State<CaminoDelDia> with _PresenciaCamino<CaminoDelDia> {
  void _tocar() {
    HapticFeedback.selectionClick();
    if (!Caminante.instancia.activado) {
      unawaited(activarCamino(context));
    } else {
      abrirCaminoDelDia(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Caminante c = Caminante.instancia;
    final bool conMapa = c.activado && c.estado == EstadoCamino.activo && c.posicion != null;
    return Semantics(
      button: true,
      label: 'Camino del día',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tocar,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TempleRadius.tarjeta),
          child: Container(
            height: widget.altura,
            decoration: BoxDecoration(
              color: EstiloCamino.fondo(),
              border: Border.all(color: TempleColors.borde),
              borderRadius: BorderRadius.circular(TempleRadius.tarjeta),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (conMapa) ...<Widget>[
                  const IgnorePointer(child: MapaCamino(interactivo: false)),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const <double>[0, 0.26, 0.6, 1],
                          colors: <Color>[
                            EstiloCamino.fondo().withValues(alpha: 0.6),
                            EstiloCamino.fondo().withValues(alpha: 0),
                            EstiloCamino.fondo().withValues(alpha: 0),
                            EstiloCamino.fondo().withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else
                  EscenaViva(
                    vitalidad: widget.vitalidad,
                    entrenoHoy: widget.entrenoHoy,
                    altura: widget.altura,
                    pie: const SizedBox.shrink(),
                  ),
                Positioned(left: 12, top: 12, child: _Insignia(enVivo: c.gpsEnVivo)),
                if (conMapa) Positioned(right: 10, bottom: c.activado ? 72 : 10, child: const _Atribucion()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (!conMapa) _Invitacion(c: c, compacta: c.activado),
                      if (c.activado) _Cifras(c: c),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.enVivo});
  final bool enVivo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: TempleColors.negro.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(TempleRadius.pastilla),
        border: Border.all(color: TempleColors.borde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('歩', style: TextStyle(fontSize: 13, color: TempleColors.violetaClaro, height: 1.1)),
          const SizedBox(width: 6),
          const Text(
            'Camino del día',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TempleColors.texto),
          ),
          if (enVivo) ...<Widget>[
            const SizedBox(width: 8),
            const _PuntoVivo(),
            const SizedBox(width: 5),
            const Text('En vivo', style: TextStyle(fontSize: 11, color: TempleColors.textoSuave)),
          ],
        ],
      ),
    );
  }
}

class _PuntoVivo extends StatefulWidget {
  const _PuntoVivo();

  @override
  State<_PuntoVivo> createState() => _PuntoVivoState();
}

class _PuntoVivoState extends State<_PuntoVivo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: TempleColors.exito),
      ),
    );
  }
}

class _Atribucion extends StatelessWidget {
  const _Atribucion();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.openstreetmap.org/copyright'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: TempleColors.negro.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          EstiloCamino.atribucion,
          style: TextStyle(fontSize: 9, color: TempleColors.textoSuave),
        ),
      ),
    );
  }
}

/// Lo que se ve sobre la ilustración cuando aún no hay mapa.
class _Invitacion extends StatelessWidget {
  const _Invitacion({required this.c, this.compacta = false});
  final Caminante c;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    String titulo = '';
    String texto = '';
    String? boton;
    Future<void> Function()? accion;
    bool buscando = false;
    if (!c.activado) {
      titulo = 'Tu camino del día';
      texto = 'Mira dónde estás y cuenta tus pasos, kilómetros y calorías.';
      boton = 'Activar';
      accion = () => activarCamino(context);
    } else {
      switch (c.estado) {
        case EstadoCamino.sinPermiso:
          titulo = 'Falta el permiso de ubicación';
          texto = 'Tus pasos se siguen contando. Permítela para ver el mapa.';
          boton = 'Permitir';
          accion = c.pedirUbicacion;
        case EstadoCamino.bloqueado:
          titulo = 'La ubicación está bloqueada';
          texto = 'Actívala para Temple en los ajustes del teléfono.';
          boton = 'Abrir ajustes';
          accion = () async {
            await geo.Geolocator.openAppSettings();
          };
        case EstadoCamino.gpsApagado:
          titulo = 'La ubicación del teléfono está apagada';
          texto = 'Enciéndela para ver dónde estás.';
          boton = 'Encender';
          accion = () async {
            await geo.Geolocator.openLocationSettings();
          };
        case EstadoCamino.apagado:
        case EstadoCamino.activo:
          titulo = 'Buscando tu ubicación…';
          texto = 'Si tarda, sal a un lugar abierto.';
          buscando = true;
      }
    }
    final Future<void> Function()? hacer = accion;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, compacta ? 10 : 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!c.activado) ...<Widget>[
            const Text(
              '一歩ずつ',
              style: TextStyle(
                fontSize: 19,
                height: 1.4,
                letterSpacing: 3,
                color: ColoresTradicion.blancoLuna,
                shadows: <Shadow>[Shadow(color: Colors.black87, blurRadius: 12)],
              ),
            ),
            const SizedBox(height: 2),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (buscando) ...<Widget>[
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: ColoresTradicion.violetaClaro),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: ColoresTradicion.blancoLuna,
                    shadows: <Shadow>[Shadow(color: Colors.black87, blurRadius: 10)],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: ColoresTradicion.texto.withValues(alpha: 0.86),
              shadows: const <Shadow>[Shadow(color: Colors.black87, blurRadius: 10)],
            ),
          ),
          if (boton != null && hacer != null) ...<Widget>[
            const SizedBox(height: 10),
            _Pastilla(texto: boton, onTap: () => unawaited(hacer())),
          ],
        ],
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.texto, required this.onTap});
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TempleColors.violeta,
      borderRadius: BorderRadius.circular(TempleRadius.pastilla),
      child: InkWell(
        borderRadius: BorderRadius.circular(TempleRadius.pastilla),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(
            texto,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _Cifras extends StatelessWidget {
  const _Cifras({required this.c});
  final Caminante c;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      decoration: BoxDecoration(
        color: TempleColors.negro.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TempleColors.borde),
      ),
      child: Row(
        children: <Widget>[
          AnilloCamino(progreso: c.progreso, tam: 34),
          const SizedBox(width: 10),
          Expanded(child: _Cifra(valor: miles(c.pasosHoy), unidad: 'pasos')),
          const _Raya(),
          Expanded(child: _Cifra(valor: kmTexto(c.km), unidad: 'km')),
          const _Raya(),
          Expanded(child: _Cifra(valor: '${c.kcal.round()}', unidad: 'kcal')),
        ],
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.valor, required this.unidad});
  final String valor;
  final String unidad;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            valor,
            maxLines: 1,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TempleColors.blancoLuna),
          ),
        ),
        Text(unidad, style: const TextStyle(fontSize: 11, color: TempleColors.textoSuave)),
      ],
    );
  }
}

class _Raya extends StatelessWidget {
  const _Raya();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, color: TempleColors.borde, margin: const EdgeInsets.symmetric(horizontal: 4));
}

/// Anillo de la meta diaria de pasos.
class AnilloCamino extends StatelessWidget {
  const AnilloCamino({super.key, required this.progreso, this.tam = 34, this.grosor = 3.5, this.centro});
  final double progreso;
  final double tam;
  final double grosor;
  final Widget? centro;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tam,
      height: tam,
      child: CustomPaint(
        painter: _AnilloPainter(
          progreso: progreso,
          grosor: grosor,
          pista: TempleColors.borde,
          color: TempleColors.violeta,
        ),
        child: Center(
          child: centro ??
              Icon(
                progreso >= 1 ? Icons.check_rounded : Icons.directions_walk_rounded,
                size: tam * 0.5,
                color: TempleColors.violetaClaro,
              ),
        ),
      ),
    );
  }
}

class _AnilloPainter extends CustomPainter {
  const _AnilloPainter({required this.progreso, required this.grosor, required this.pista, required this.color});
  final double progreso;
  final double grosor;
  final Color pista;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = (Offset.zero & size).deflate(grosor / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = grosor
        ..color = pista,
    );
    if (progreso > 0) {
      canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * progreso.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = grosor
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_AnilloPainter o) => o.progreso != progreso || o.color != color || o.pista != pista;
}

// ---------------------------------------------------------------------------
// 61.5 AVISO ANTES DE PEDIR PERMISOS
// ---------------------------------------------------------------------------

/// Explica qué se usa y para qué antes de que el teléfono pida los permisos.
Future<void> activarCamino(BuildContext context) async {
  final bool? si = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => const _AvisoCamino(),
  );
  if (si != true) return;
  await Caminante.instancia.activar();
}

class _AvisoCamino extends StatelessWidget {
  const _AvisoCamino();

  @override
  Widget build(BuildContext context) {
    Widget fila(IconData icono, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icono, size: 19, color: TempleColors.violetaClaro),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(texto, style: const TextStyle(fontSize: 13, height: 1.45, color: TempleColors.texto)),
              ),
            ],
          ),
        );
    return Dialog(
      backgroundColor: TempleColors.grafito,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: TempleColors.borde),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TempleColors.moradoProfundo,
                  border: Border.all(color: TempleColors.violeta.withValues(alpha: 0.55)),
                ),
                child: const Icon(Icons.route_rounded, size: 28, color: TempleColors.violetaClaro),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tu camino del día',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: TempleColors.blancoLuna),
            ),
            const SizedBox(height: 6),
            const Text(
              'Para mostrarte en el mapa y contar tus pasos, Temple usa:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: TempleColors.textoSuave),
            ),
            const SizedBox(height: 16),
            fila(Icons.my_location_rounded,
                'Tu ubicación, solo mientras la app está abierta, para mostrarte en el mapa y medir tu recorrido.'),
            fila(Icons.directions_walk_rounded,
                'El sensor de pasos del teléfono, para contar tus pasos del día aunque la app esté cerrada.'),
            fila(Icons.lock_outline_rounded,
                'Tu ubicación, tu recorrido y tus pasos se quedan en este teléfono. No se guardan en tu cuenta ni se ven en el Clan.'),
            fila(Icons.map_outlined, 'El mapa se descarga de OpenFreeMap (datos de OpenStreetMap) según la zona que se ve.'),
            const SizedBox(height: 4),
            const Text(
              'Los kilómetros y las calorías son aproximados: salen de tus pasos, tu estatura y tu peso.',
              style: TextStyle(fontSize: 12, height: 1.45, color: TempleColors.textoTenue),
            ),
            const SizedBox(height: 18),
            DojoPrimaryButton(texto: 'Continuar', onPressed: () => Navigator.of(context).pop(true)),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Ahora no', style: TextStyle(color: TempleColors.textoSuave)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 61.6 PANTALLA DEL CAMINO: mapa grande, cifras, semana y ajustes
// ---------------------------------------------------------------------------

void abrirCaminoDelDia(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CaminoDelDiaScreen()));
}

class CaminoDelDiaScreen extends StatefulWidget {
  const CaminoDelDiaScreen({super.key});

  @override
  State<CaminoDelDiaScreen> createState() => _CaminoDelDiaScreenState();
}

class _CaminoDelDiaScreenState extends State<CaminoDelDiaScreen> with _PresenciaCamino<CaminoDelDiaScreen> {
  Future<void> _pedirEstatura() async {
    final Caminante c = Caminante.instancia;
    final TextEditingController campo = TextEditingController(text: c.estaturaCm?.toString() ?? '');
    final int? cm = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: TempleColors.grafito,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: TempleColors.borde),
        ),
        title: const Text('Tu estatura', style: TextStyle(color: TempleColors.blancoLuna, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Con ella calculamos el largo de tu paso y los kilómetros. Se queda en este teléfono.',
              style: TextStyle(fontSize: 13, height: 1.45, color: TempleColors.textoSuave),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: campo,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              maxLength: 3,
              style: const TextStyle(color: TempleColors.blancoLuna, fontSize: 18),
              decoration: const InputDecoration(
                suffixText: 'cm',
                hintText: '170',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          if (c.estaturaCm != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(0),
              child: const Text('Quitar', style: TextStyle(color: TempleColors.textoSuave)),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: TempleColors.textoSuave)),
          ),
          TextButton(
            onPressed: () {
              final int? v = int.tryParse(campo.text.trim());
              if (v == null || v < 120 || v > 230) {
                avisoClan(ctx, 'Escribe tu estatura en centímetros, entre 120 y 230.', error: true);
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Guardar', style: TextStyle(color: TempleColors.violetaClaro, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    campo.dispose();
    if (cm == null) return;
    await c.ponerEstatura(cm == 0 ? null : cm);
  }

  Future<void> _elegirMeta() async {
    final Caminante c = Caminante.instancia;
    const List<int> opciones = <int>[4000, 6000, 8000, 10000, 12000, 15000];
    final int? elegida = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: TempleColors.grafito,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (BuildContext ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Meta diaria de pasos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: TempleColors.blancoLuna),
              ),
              const SizedBox(height: 6),
              const Text(
                'Empieza por una que puedas cumplir casi todos los días.',
                style: TextStyle(fontSize: 13, color: TempleColors.textoSuave),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final int o in opciones)
                    ChoiceChip(
                      label: Text(miles(o)),
                      selected: o == c.meta,
                      onSelected: (_) => Navigator.of(ctx).pop(o),
                      selectedColor: TempleColors.violeta,
                      backgroundColor: TempleColors.superficie,
                      labelStyle: TextStyle(
                        color: o == c.meta ? Colors.white : TempleColors.texto,
                        fontWeight: FontWeight.w600,
                      ),
                      side: const BorderSide(color: TempleColors.borde),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (elegida != null) await c.ponerMeta(elegida);
  }

  String _ritmo(double v) {
    if (v < 0.5) return '—';
    final int seg = (1000 / v).round();
    if (seg > 30 * 60) return '—';
    return '${seg ~/ 60}:${(seg % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Caminante c = Caminante.instancia;
    final bool conMapa = c.activado && c.estado == EstadoCamino.activo && c.posicion != null;
    final EdgeInsets borde = MediaQuery.paddingOf(context);
    final double altoMapa = MediaQuery.sizeOf(context).height * 0.48;
    return Scaffold(
      backgroundColor: TempleColors.negro,
      body: Column(
        children: <Widget>[
          SizedBox(
            height: altoMapa,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (conMapa)
                  const MapaCamino(interactivo: true, zoom: 16.6)
                else
                  ColoredBox(
                    color: EstiloCamino.fondo(),
                    child: Align(
                      alignment: const Alignment(0, 0.3),
                      child: _Invitacion(c: c),
                    ),
                  ),
                Positioned(
                  left: 12,
                  top: borde.top + 8,
                  child: _BotonRedondo(
                    icono: Icons.arrow_back_rounded,
                    etiqueta: 'Volver',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: borde.top + 14,
                  child: IgnorePointer(child: Center(child: _Insignia(enVivo: c.gpsEnVivo))),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + borde.bottom),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AnilloCamino(
                      progreso: c.progreso,
                      tam: 78,
                      grosor: 6,
                      centro: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '${(c.progreso * 100).round()}%',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: TempleColors.blancoLuna),
                          ),
                          const Text('de la meta', style: TextStyle(fontSize: 9.5, color: TempleColors.textoSuave)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            miles(c.pasosHoy),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: TempleColors.blancoLuna,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            'pasos hoy · meta ${miles(c.meta)}',
                            style: const TextStyle(fontSize: 13, color: TempleColors.textoSuave),
                          ),
                          if (c.activado && c.pasosConGps) ...<Widget>[
                            const SizedBox(height: 4),
                            const Text(
                              'Contados con el GPS mientras la app está abierta.',
                              style: TextStyle(fontSize: 11.5, color: TempleColors.textoTenue),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(child: _Dato(titulo: 'Distancia', valor: '${kmTexto(c.km)} km')),
                    const SizedBox(width: 10),
                    Expanded(child: _Dato(titulo: 'Calorías', valor: '${c.kcal.round()} kcal')),
                    const SizedBox(width: 10),
                    Expanded(child: _Dato(titulo: 'Ritmo', valor: _ritmo(c.velocidad), unidad: c.velocidad >= 0.5 ? 'min/km' : null)),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Esta semana',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TempleColors.blancoLuna),
                ),
                const SizedBox(height: 12),
                _Semana(c: c),
                const SizedBox(height: 22),
                _Ajuste(
                  icono: Icons.height_rounded,
                  titulo: 'Tu estatura',
                  valor: c.estaturaCm == null ? 'Sin dato: usamos ${c.estaturaUsada} cm' : '${c.estaturaCm} cm',
                  onTap: _pedirEstatura,
                ),
                const SizedBox(height: 10),
                _Ajuste(
                  icono: Icons.flag_outlined,
                  titulo: 'Meta diaria',
                  valor: '${miles(c.meta)} pasos',
                  onTap: _elegirMeta,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tu ubicación y tu recorrido se quedan en este teléfono: no se guardan en tu cuenta ni se ven en el '
                  'Clan. El GPS solo funciona con la app abierta. Los kilómetros y las calorías son aproximados.',
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: TempleColors.textoTenue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.titulo, required this.valor, this.unidad});
  final String titulo;
  final String valor;
  final String? unidad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: TempleColors.superficie,
        borderRadius: BorderRadius.circular(TempleRadius.campo),
        border: Border.all(color: TempleColors.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(titulo, style: const TextStyle(fontSize: 11.5, color: TempleColors.textoSuave)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TempleColors.blancoLuna),
            ),
          ),
          if (unidad != null) Text(unidad!, style: const TextStyle(fontSize: 10.5, color: TempleColors.textoTenue)),
        ],
      ),
    );
  }
}

class _Semana extends StatelessWidget {
  const _Semana({required this.c});
  final Caminante c;

  @override
  Widget build(BuildContext context) {
    const List<String> letras = <String>['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final DateTime ahora = DateTime.now();
    final List<DateTime> dias = <DateTime>[
      for (int i = 6; i >= 0; i--) DateTime(ahora.year, ahora.month, ahora.day - i),
    ];
    final List<int> pasos = <int>[for (final DateTime d in dias) c.pasosDe(Caminante.fecha(d))];
    final int tope = math.max(c.meta, pasos.fold<int>(0, math.max));
    return SizedBox(
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      pasos[i] >= 1000 ? '${(pasos[i] / 1000).toStringAsFixed(1).replaceAll('.', ',')}k' : '${pasos[i]}',
                      style: const TextStyle(fontSize: 9.5, color: TempleColors.textoTenue),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: math.max(4.0, 70.0 * (tope <= 0 ? 0 : pasos[i] / tope)),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: i == 6
                            ? TempleColors.violeta
                            : pasos[i] >= c.meta
                                ? TempleColors.violetaClaro.withValues(alpha: 0.75)
                                : TempleColors.bordeVivo,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      letras[dias[i].weekday - 1],
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: i == 6 ? FontWeight.w700 : FontWeight.w500,
                        color: i == 6 ? TempleColors.violetaClaro : TempleColors.textoSuave,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Ajuste extends StatelessWidget {
  const _Ajuste({required this.icono, required this.titulo, required this.valor, required this.onTap});
  final IconData icono;
  final String titulo;
  final String valor;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TempleColors.superficie,
      borderRadius: BorderRadius.circular(TempleRadius.campo),
      child: InkWell(
        borderRadius: BorderRadius.circular(TempleRadius.campo),
        onTap: () {
          HapticFeedback.selectionClick();
          unawaited(onTap());
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TempleRadius.campo),
            border: Border.all(color: TempleColors.borde),
          ),
          child: Row(
            children: <Widget>[
              Icon(icono, size: 20, color: TempleColors.violetaClaro),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      titulo,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TempleColors.blancoLuna),
                    ),
                    const SizedBox(height: 2),
                    Text(valor, style: const TextStyle(fontSize: 12.5, color: TempleColors.textoSuave)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: TempleColors.textoTenue),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({required this.icono, required this.etiqueta, required this.onTap});
  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: etiqueta,
      child: Material(
        color: TempleColors.negro.withValues(alpha: 0.78),
        shape: const CircleBorder(side: BorderSide(color: TempleColors.borde)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icono, size: 21, color: TempleColors.blancoLuna),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 61.7 NÚMEROS A LA COLOMBIANA
// ---------------------------------------------------------------------------

/// 7421 → «7.421».
String miles(int n) {
  final String s = n.abs().toString();
  final StringBuffer b = StringBuffer(n < 0 ? '-' : '');
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// 3.14159 → «3,14»; 12.5 → «12,5».
String kmTexto(double km) => km.toStringAsFixed(km < 10 ? 2 : 1).replaceAll('.', ',');
