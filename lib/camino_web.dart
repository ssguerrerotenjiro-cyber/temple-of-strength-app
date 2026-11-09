// En el navegador no hay Camino del día: el Dojo muestra en su lugar la
// tarjeta que invita a instalar la app (CaminoEnWeb, sección 61 de main.dart).
// Este archivo existe para que la web no compile el mapa, el GPS ni el sensor
// de pasos, que solo viven en la app instalada (camino_app.dart).
import 'package:flutter/widgets.dart';

Widget bannerCamino({required double vitalidad, required bool entrenoHoy}) => const SizedBox.shrink();
