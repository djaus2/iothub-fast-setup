$jobs = Get-Job | Where-Object { $_.Name -like 'iot-device*' }
if ($jobs) {
  $jobs | Stop-Job -ErrorAction SilentlyContinue
  $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
  'Stopped/removed jobs: ' + ($jobs.Name -join ', ')
} else {
  'No matching iot emulator jobs found.'
}
