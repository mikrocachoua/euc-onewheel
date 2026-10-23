// Conversión de unidades para mostrar telemetría y viajes según
// las preferencias del usuario (sistema métrico o imperial,
// °C/°F, bar/psi). Funciones puras, sin estado.

/// Velocidad: km/h → mph si el usuario usa sistema imperial.
double displaySpeed(double kmh, {required bool imperial}) =>
    imperial ? kmh * 0.621371 : kmh;

String speedUnit({required bool imperial}) => imperial ? 'mph' : 'km/h';

/// Distancia: km → millas si el usuario usa sistema imperial.
double displayDistanceKm(double km, {required bool imperial}) =>
    imperial ? km * 0.621371 : km;

String distanceUnit({required bool imperial}) => imperial ? 'mi' : 'km';

/// Temperatura: °C → °F si el usuario lo eligió.
double displayTemp(double celsius, {required bool fahrenheit}) =>
    fahrenheit ? celsius * 9 / 5 + 32 : celsius;

String tempUnit({required bool fahrenheit}) => fahrenheit ? '°F' : '°C';

/// Presión: bar → psi si el usuario lo eligió.
double displayPressure(double bar, {required bool psi}) =>
    psi ? bar * 14.5038 : bar;

String pressureUnit({required bool psi}) => psi ? 'psi' : 'bar';
