# Boolooavatar local server for Windows. No installation needed.
# Run it by double-clicking start-windows.bat (it asks for administrator permission).
$ErrorActionPreference = 'Stop'
$port = 8765
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

$code = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;

public class BServer
{
    public static string Dir = ".";
    public static bool Lan = false;
    static List<StreamWriter> clients = new List<StreamWriter>();
    static object lk = new object();

    public static void Run(int port)
    {
        HttpListener l = new HttpListener();
        try
        {
            l.Prefixes.Add("http://+:" + port + "/");
            l.Start();
            Lan = true;
        }
        catch (HttpListenerException)
        {
            l = new HttpListener();
            l.Prefixes.Add("http://localhost:" + port + "/");
            l.Start();
            Lan = false;
        }
        Console.WriteLine(Lan ? "LAN mode: phone can connect." : "WARNING: local-only mode (not started as administrator). The phone cannot connect.");
        while (true)
        {
            HttpListenerContext ctx = l.GetContext();
            ThreadPool.QueueUserWorkItem(delegate(object o) { Handle((HttpListenerContext)o); }, ctx);
        }
    }

    static void Bytes(HttpListenerContext c, byte[] b, string ct, int code)
    {
        HttpListenerResponse r = c.Response;
        r.StatusCode = code;
        r.ContentType = ct;
        r.Headers.Add("Cache-Control", "no-store");
        r.ContentLength64 = b.Length;
        r.OutputStream.Write(b, 0, b.Length);
        r.OutputStream.Close();
    }

    static void Text(HttpListenerContext c, string s, int code)
    {
        Bytes(c, Encoding.UTF8.GetBytes(s), "text/plain; charset=utf-8", code);
    }

    static void Handle(HttpListenerContext c)
    {
        try
        {
            string p = c.Request.Url.AbsolutePath;
            if (p == "/ping") { Text(c, "boolooavatar", 200); return; }
            if (p == "/status")
            {
                int n;
                lock (lk) { n = clients.Count; }
                Text(c, n.ToString(), 200);
                return;
            }
            if (p == "/events") { Events(c); return; }
            if (p == "/cmd" && c.Request.HttpMethod == "POST")
            {
                string body;
                using (StreamReader r = new StreamReader(c.Request.InputStream, Encoding.UTF8)) { body = r.ReadToEnd(); }
                Broadcast(body.Replace("\r", " ").Replace("\n", " "));
                Text(c, "ok", 200);
                return;
            }
            string f = null;
            if (p == "/" || p == "/index.html" || p == "/boolooavatar-v3.html") f = "boolooavatar-v3.html";
            else if (p == "/remote" || p == "/remote.html") f = "remote.html";
            if (f != null)
            {
                string path = Path.Combine(Dir, f);
                if (File.Exists(path)) { Bytes(c, File.ReadAllBytes(path), "text/html; charset=utf-8", 200); return; }
                Text(c, "File not found: " + f, 404);
                return;
            }
            Text(c, "Not found", 404);
        }
        catch (Exception)
        {
            try { c.Response.Abort(); } catch (Exception) { }
        }
    }

    static void Events(HttpListenerContext c)
    {
        HttpListenerResponse resp = c.Response;
        resp.ContentType = "text/event-stream";
        resp.Headers.Add("Cache-Control", "no-store");
        resp.SendChunked = true;
        StreamWriter sw = new StreamWriter(resp.OutputStream, new UTF8Encoding(false));
        sw.AutoFlush = true;
        lock (lk) { clients.Add(sw); }
        try
        {
            lock (sw) { sw.Write(": hi\n\n"); }
            while (true)
            {
                Thread.Sleep(10000);
                lock (sw) { sw.Write(": ka\n\n"); }
            }
        }
        catch (Exception) { }
        finally
        {
            lock (lk) { clients.Remove(sw); }
            try { resp.Abort(); } catch (Exception) { }
        }
    }

    static void Broadcast(string msg)
    {
        List<StreamWriter> snap;
        lock (lk) { snap = new List<StreamWriter>(clients); }
        foreach (StreamWriter sw in snap)
        {
            try { lock (sw) { sw.Write("data: " + msg + "\n\n"); } }
            catch (Exception) { lock (lk) { clients.Remove(sw); } }
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $code -Language CSharp
} catch {
    Write-Host "Could not start the server: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Allow the phone to reach the server (private/domain networks)
try {
    Remove-NetFirewallRule -DisplayName 'Boolooavatar' -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'Boolooavatar' -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Private,Domain | Out-Null
} catch { }

# Find this PC's Wi-Fi/LAN address
$ip = 'YOUR-PC-IP'
try {
    $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if ($cfg) { $ip = $cfg.IPv4Address.IPAddress }
} catch { }

Write-Host ''
Write-Host 'Boolooavatar server is running. Keep this window open.' -ForegroundColor Green
Write-Host ''
Write-Host "  On this PC:               http://localhost:$port/"
Write-Host "  Avatar only (for OBS):    http://localhost:$port/#clean"
Write-Host "  Phone remote (same Wi-Fi): http://${ip}:$port/remote"
Write-Host ''
Write-Host '  If the phone cannot connect: set your Wi-Fi network profile to Private (Windows Settings > Network).'
Write-Host ''

[BServer]::Dir = $dir
[BServer]::Run($port)
