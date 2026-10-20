$conn = New-Object System.Data.SqlClient.SqlConnection('Server=127.0.0.1,1433;Database=SkyGo_Cnpm;Integrated Security=True;TrustServerCertificate=True;')
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 'SELECT MaChuyenBay, SoHieuChuyen, GioCatCanh, GioDenDuKien, TrangThai, SYSUTCDATETIME() AS HienTaiUTC FROM CHUYEN_BAY ORDER BY GioCatCanh'
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable
    $adapter.Fill($dt) | Out-Null
    $dt | Format-Table -AutoSize
} catch {
    Write-Output $_.Exception.Message
} finally {
    $conn.Close()
}
