String dashboardGreeting(DateTime time) {
  if (time.hour >= 5 && time.hour < 12) return 'Buenos días';
  if (time.hour >= 12 && time.hour < 20) return 'Buenas tardes';
  return 'Buenas noches';
}
