# Regenerates graphics/dust-ring.png — the procedural dust torus used by the
# continuous blast wave. Run from the mod root: pwsh tools/generate-dust-ring.ps1
# Tweak the harmonics/colors below and re-run to taste.
Add-Type -ReferencedAssemblies System.Drawing.Common, System.Drawing.Primitives, System.Runtime.InteropServices -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class DustRing {
    public static void Generate(string path, int size) {
        var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        var rect = new Rectangle(0, 0, size, size);
        var data = bmp.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        var bytes = new byte[data.Stride * size];
        double c = (size - 1) / 2.0;
        var rnd = new Random(42); // fixed seed -> reproducible texture
        double ph1 = rnd.NextDouble() * 6.283, ph2 = rnd.NextDouble() * 6.283, ph3 = rnd.NextDouble() * 6.283;
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                double dx = (x - c) / c, dy = (y - c) / c;
                double r = Math.Sqrt(dx * dx + dy * dy);
                double a = Math.Atan2(dy, dx);
                // wobble the ring radius and width by angle so it reads as dust, not a compass circle
                double wob = 1.0 + 0.06 * Math.Sin(5 * a + ph1) + 0.04 * Math.Sin(9 * a + ph2) + 0.03 * Math.Sin(17 * a + ph3);
                double ringR = 0.60 * wob;
                double width = 0.20 * (1.0 + 0.30 * Math.Sin(7 * a + ph2));
                double d = (r - ringR) / width;
                double alpha = 1.35 * Math.Exp(-d * d); // boosted density
                if (r < ringR) alpha = Math.Max(alpha, 0.38 * (r / ringR)); // thicker interior haze
                if (r > 0.97) alpha *= Math.Max(0.0, (1.0 - r) / 0.03);     // hard outer cutoff
                alpha *= 0.80 + 0.20 * rnd.NextDouble();                     // speckle grit
                int A = (int)(Math.Min(1.0, alpha) * 255);
                // darker, more saturated smoke for contrast against dirt terrain
                double shade = 0.80 + 0.20 * Math.Min(1.0, Math.Max(0.0, d));
                int R = (int)(96 * shade), G = (int)(78 * shade), B = (int)(62 * shade);
                int i = y * data.Stride + x * 4;
                bytes[i] = (byte)B; bytes[i + 1] = (byte)G; bytes[i + 2] = (byte)R; bytes[i + 3] = (byte)A;
            }
        }
        Marshal.Copy(bytes, 0, data.Scan0, bytes.Length);
        bmp.UnlockBits(data);
        bmp.Save(path, ImageFormat.Png);
        bmp.Dispose();
    }

    // Soft glow ring for the blast front: pure gaussian profile, no hard edges.
    // White-warm; tinted orange and faded at runtime.
    public static void GenerateGlow(string path, int size) {
        var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        var rect = new Rectangle(0, 0, size, size);
        var data = bmp.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        var bytes = new byte[data.Stride * size];
        double c = (size - 1) / 2.0;
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                double dx = (x - c) / c, dy = (y - c) / c;
                double r = Math.Sqrt(dx * dx + dy * dy);
                double d = (r - 0.60) / 0.10;
                double alpha = Math.Exp(-d * d);
                if (r > 0.97) alpha *= Math.Max(0.0, (1.0 - r) / 0.03);
                int A = (int)(Math.Min(1.0, alpha) * 255);
                int i = y * data.Stride + x * 4;
                bytes[i] = 215; bytes[i + 1] = 240; bytes[i + 2] = 255; bytes[i + 3] = (byte)A;
            }
        }
        Marshal.Copy(bytes, 0, data.Scan0, bytes.Length);
        bmp.UnlockBits(data);
        bmp.Save(path, ImageFormat.Png);
        bmp.Dispose();
    }

    // Tracer streak: vertical, tail at top fading to nothing, bright head at the
    // bottom. Gaussian cross-section (soft core + wide faint halo) — no hard
    // edges anywhere, so it never reads as a pixelated line.
    public static void GenerateTracer(string path, int w, int h) {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        var rect = new Rectangle(0, 0, w, h);
        var data = bmp.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        var bytes = new byte[data.Stride * h];
        double cx = (w - 1) / 2.0;
        for (int y = 0; y < h; y++) {
            double t = (double)y / (h - 1); // 0 = tail (top), 1 = head (bottom)
            double along = Math.Pow(t, 1.6); // smooth ramp from nothing
            double head = 0.55 * Math.Exp(-Math.Pow((t - 0.965) / 0.03, 2)); // bright head bulb
            for (int x = 0; x < w; x++) {
                double dx = x - cx;
                double core = Math.Exp(-dx * dx / (2 * 5.0 * 5.0));
                double halo = Math.Exp(-dx * dx / (2 * 15.0 * 15.0));
                double alpha = (core * 0.95 + halo * 0.35) * (along + head);
                int A = (int)(Math.Min(1.0, alpha) * 255);
                int i = y * data.Stride + x * 4;
                bytes[i] = 205; bytes[i + 1] = 235; bytes[i + 2] = 255; bytes[i + 3] = (byte)A;
            }
        }
        Marshal.Copy(bytes, 0, data.Scan0, bytes.Length);
        bmp.UnlockBits(data);
        bmp.Save(path, ImageFormat.Png);
        bmp.Dispose();
    }
}
'@
[DustRing]::Generate("$PWD\graphics\dust-ring.png", 512)
[DustRing]::GenerateGlow("$PWD\graphics\glow-ring.png", 512)
[DustRing]::GenerateTracer("$PWD\graphics\tracer.png", 64, 512)
Write-Host "graphics: dust-ring.png, glow-ring.png, tracer.png regenerated."
