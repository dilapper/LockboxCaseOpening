# Ray-casts a small stylised 3D lockbox (wood body + riveted metal bands/frame) and writes two
# 512x512 TGAs: case_wood.tga (full colour) and case_metal.tga (greyscale, tinted per box in-game).
# (circle_hole.tga, the spinner cut-out, comes from make_circle_hole.ps1.)
# Usage: pwsh tools/make_case_art.ps1 <output-dir>
param([Parameter(Mandatory)][string]$Out)

if (-not ('CaseArt' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.IO;
public static class CaseArt {
    const int N = 512, SS = 4;
    const double YAW = -0.60, PITCH = 0.42, SCALE = 170.0, CY = 330.0;
    const double HX = 1.0, HZ = 0.62, BH = 0.72, LB = 0.50; // half length, half depth, body height, lid height
    const double TMAX = Math.PI * 0.55;                     // arc length coord of the lid (0 front .. TMAX back)

    struct V { public double x, y, z; public V(double a, double b, double c) { x = a; y = b; z = c; } }
    static V Ry(V p, double t) { double c = Math.Cos(t), s = Math.Sin(t); return new V(p.x * c + p.z * s, p.y, -p.x * s + p.z * c); }
    static V Rx(V p, double t) { double c = Math.Cos(t), s = Math.Sin(t); return new V(p.x, p.y * c - p.z * s, p.y * s + p.z * c); }
    static V ToObj(V v) { return Ry(Rx(v, -PITCH), -YAW); }
    static double Dot(V a, V b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
    static V Norm(V a) { double l = Math.Sqrt(Dot(a, a)); return new V(a.x / l, a.y / l, a.z / l); }
    static V Add(V a, V b) { return new V(a.x + b.x, a.y + b.y, a.z + b.z); }
    static V Mul(V a, double k) { return new V(a.x * k, a.y * k, a.z * k); }
    static double Clamp(double v, double a, double b) { return v < a ? a : (v > b ? b : v); }
    static double Smooth(double t) { t = Clamp(t, 0, 1); return t * t * (3 - 2 * t); }
    static double Lerp(double a, double b, double t) { return a + (b - a) * t; }

    // ---- noise ----
    static double Hash(double x, double y) { double h = Math.Sin(x * 127.1 + y * 311.7) * 43758.5453; return h - Math.Floor(h); }
    static double VNoise(double x, double y) {
        double ix = Math.Floor(x), iy = Math.Floor(y), fx = x - ix, fy = y - iy;
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
        double a = Hash(ix, iy), b = Hash(ix + 1, iy), c = Hash(ix, iy + 1), d = Hash(ix + 1, iy + 1);
        return Lerp(Lerp(a, b, fx), Lerp(c, d, fx), fy);
    }
    static double Fbm(double x, double y) { return 0.55 * VNoise(x, y) + 0.3 * VNoise(x * 2.1, y * 2.1) + 0.15 * VNoise(x * 4.3, y * 4.3); }

    // ---- ray casting: ids 1 front(+z) 2 back 3 right(+x) 4 left 5 base 6 lid 7 cap+x 8 cap-x ----
    static int Cast(V o, V d, out double tHit, out V n, out V p) {
        tHit = 1e30; n = new V(0, 1, 0); p = o; int id = 0;
        double[] mn = { -HX, 0, -HZ }, mx = { HX, BH, HZ };
        double[] oo = { o.x, o.y, o.z }, dd = { d.x, d.y, d.z };
        double t0 = -1e30, t1 = 1e30; int axis = 0, sign = 1;
        for (int i = 0; i < 3; i++) {
            if (Math.Abs(dd[i]) < 1e-9) { if (oo[i] < mn[i] || oo[i] > mx[i]) { t0 = 1e30; break; } continue; }
            double a = (mn[i] - oo[i]) / dd[i], b = (mx[i] - oo[i]) / dd[i];
            if (a > b) { double tmp = a; a = b; b = tmp; }
            if (a > t0) { t0 = a; axis = i; sign = dd[i] > 0 ? -1 : 1; }
            if (b < t1) t1 = b;
        }
        if (t0 <= t1 && t0 > 0 && t0 < 1e29) {
            tHit = t0;
            double[] nn = { 0, 0, 0 }; nn[axis] = sign; n = new V(nn[0], nn[1], nn[2]);
            id = axis == 2 ? (sign > 0 ? 1 : 2) : axis == 0 ? (sign > 0 ? 3 : 4) : 5;
            if (axis == 1 && sign > 0) id = 0;
        }
        double a2 = HZ * HZ, b2 = LB * LB;
        double A = d.z * d.z / a2 + d.y * d.y / b2;
        double B = 2 * (o.z * d.z / a2 + (o.y - BH) * d.y / b2);
        double C = o.z * o.z / a2 + (o.y - BH) * (o.y - BH) / b2 - 1;
        double disc = B * B - 4 * A * C;
        if (A > 1e-12 && disc >= 0) {
            double sq = Math.Sqrt(disc);
            double[] ts = { (-B - sq) / (2 * A), (-B + sq) / (2 * A) };
            foreach (double t in ts) {
                if (t <= 0 || t >= tHit) continue;
                V q = new V(o.x + d.x * t, o.y + d.y * t, o.z + d.z * t);
                if (q.y >= BH && Math.Abs(q.x) <= HX) {
                    tHit = t; id = 6; p = q;
                    n = Norm(new V(0, (q.y - BH) / b2, q.z / a2));
                    break;
                }
            }
        }
        for (int s = -1; s <= 1; s += 2) {
            if (Math.Abs(d.x) < 1e-9) continue;
            double t = (s * HX - o.x) / d.x;
            if (t <= 0 || t >= tHit) continue;
            V q = new V(s * HX, o.y + d.y * t, o.z + d.z * t);
            double ez = q.z / HZ, ey = (q.y - BH) / LB;
            if (q.y >= BH && ez * ez + ey * ey <= 1) { tHit = t; id = s > 0 ? 7 : 8; n = new V(s, 0, 0); }
        }
        if (id != 0) p = new V(o.x + d.x * tHit, o.y + d.y * tHit, o.z + d.z * tHit);
        return id;
    }

    // ---- local surface coordinates ----
    static void Local(int id, V p, out double s, out double t, out V ts, out V tt) {
        if (id == 1 || id == 2) { s = p.x; t = p.y; ts = new V(1, 0, 0); tt = new V(0, 1, 0); }
        else if (id == 6) {
            double phi = Math.Atan2((p.y - BH) / LB, p.z / HZ);
            // phi runs 0 at the front edge (z>0) up over the top to pi at the back edge
            s = p.x; t = phi * 0.55; ts = new V(1, 0, 0);
            tt = Norm(new V(0, LB * Math.Cos(phi), -HZ * Math.Sin(phi)));
            if (p.z < 0) { /* back half: phi already > pi/2 */ }
        } else { s = p.z; t = p.y; ts = new V(0, 0, 1); tt = new V(0, 1, 0); }
    }

    static double SdBox(double s, double t, double cs, double ct, double hs, double ht) { return Math.Min(hs - Math.Abs(s - cs), ht - Math.Abs(t - ct)); }

    // positive inside metal; edges wobble a little so the plates look hand-made
    static double MetalSd(int id, double s, double t) {
        return MetalSd0(id, s, t) + (VNoise(s * 11 + id * 3.7, t * 11) - 0.5) * 0.024;
    }
    static double MetalSd0(int id, double s, double t) {
        double sd = -1e9;
        if (id == 1 || id == 2 || id == 6) {
            foreach (double bx in new double[] { -0.66, 0.0, 0.66 }) sd = Math.Max(sd, (bx == 0 ? 0.14 : 0.10) - Math.Abs(s - bx));
            sd = Math.Max(sd, Math.Abs(s) - (HX - 0.11)); // end frames
        }
        if (id == 1 || id == 2) {
            sd = Math.Max(sd, 0.06 - Math.Abs(t - BH));
            sd = Math.Max(sd, 0.09 - t);
        } else if (id == 6) {
            sd = Math.Max(sd, 0.07 - t);
            sd = Math.Max(sd, 0.07 - (TMAX - t));
        } else if (id == 3 || id == 4) {
            sd = Math.Max(sd, Math.Abs(s) - (HZ - 0.11));
            sd = Math.Max(sd, 0.06 - Math.Abs(t - BH));
            sd = Math.Max(sd, 0.09 - t);
            sd = Math.Max(sd, SdBox(s, t, 0, 0.36, 0.17, 0.13)); // handle plate
        } else if (id == 7 || id == 8) {
            double e = 1 - Math.Sqrt((s / HZ) * (s / HZ) + ((t - BH) / LB) * ((t - BH) / LB));
            sd = Math.Max(sd, 0.10 - e * 0.5);
            sd = Math.Max(sd, 0.06 - (t - BH));
        }
        if (id == 1) sd = Math.Max(sd, SdBox(s, t, 0, 0.44, 0.19, 0.29)); // lock plate
        return sd;
    }

    static double RivetAt(double s, double t, double cs, double ct, double r) {
        double d = Math.Sqrt((s - cs) * (s - cs) + (t - ct) * (t - ct));
        return Math.Sqrt(Math.Max(0, 1 - (d / r) * (d / r)));
    }

    static double Rivets(int id, double s, double t) {
        double best = 0;
        if (id == 1 || id == 2) {
            foreach (double bx in new double[] { -0.66, 0.0, 0.66 })
                foreach (double ry in new double[] { 0.17, 0.57 }) {
                    if (id == 1 && bx == 0) continue; // lock plate covers the centre
                    best = Math.Max(best, RivetAt(s, t, bx, ry, 0.045));
                }
        } else if (id == 6) {
            foreach (double bx in new double[] { -0.66, 0.0, 0.66 })
                for (double ru = 0.28; ru < TMAX - 0.2; ru += 0.36)
                    best = Math.Max(best, RivetAt(s, t, bx, ru, 0.045));
        }
        if (id == 1) {
            foreach (double sx in new double[] { -0.12, 0.12 })
                foreach (double sy in new double[] { 0.24, 0.64 })
                    best = Math.Max(best, RivetAt(s, t, sx, sy, 0.035));
        }
        return best;
    }

    static double SeamSpacing(int id) { return id == 6 ? 0.34 : (id == 7 || id == 8 ? 0.2 : 0.24); }
    static double SeamDist(int id, double s, double t) {
        double sp = SeamSpacing(id);
        double f = (t + (VNoise(s * 5 + id, t * 3) - 0.5) * 0.035) / sp; // wobbly, hand-laid planks
        return Math.Abs(f - Math.Round(f)) * sp;
    }

    static double Height(int id, double s, double t) {
        double sd = MetalSd(id, s, t);
        double h = 0;
        if (sd > 0) {
            h = 0.05 * Smooth(sd / 0.028);
            h += 0.045 * Rivets(id, s, t) * Smooth(sd / 0.06);
            if (id == 1) {
                double ls = SdBox(s, t, 0, 0.44, 0.19, 0.29);
                if (ls > 0) {
                    h += 0.03 * Smooth(ls / 0.03);
                    double ky = t - 0.52;
                    double kh = Math.Sqrt(s * s + ky * ky) - 0.05;
                    double slot = Math.Max(Math.Abs(s) - 0.02, Math.Max(-ky - 0.17, ky));
                    double kd = Math.Min(kh, slot);
                    if (kd < 0) h -= 0.07;
                    else if (kd < 0.02) h -= 0.07 * (1 - kd / 0.02);
                }
            }
        } else {
            h = -0.018 * (1 - Smooth(SeamDist(id, s, t) / 0.016));
            h -= 0.006 * Fbm(s * 14 + id, t * 14); // rough, uneven wood surface
        }
        return h;
    }

    static void Wood(int id, double s, double t, out double r, out double g, out double b) {
        double sp = SeamSpacing(id);
        double k = Math.Floor(t / sp + 0.0001);
        double vr = Hash(k, 3.1) - 0.5;
        double grain = Fbm(s * 1.4 + k * 7.3, t * 26);
        double knots = Fbm(s * 5 + k, t * 5);
        double m = Clamp(0.5 + (grain - 0.5) * 1.9 + vr * 0.5 + (knots - 0.5) * 0.25, 0, 1);
        r = Lerp(0.27, 0.74, m); g = Lerp(0.15, 0.46, m); b = Lerp(0.07, 0.22, m);
        double seam = 1 - Smooth(SeamDist(id, s, t) / 0.016);
        r *= 1 - 0.65 * seam; g *= 1 - 0.65 * seam; b *= 1 - 0.65 * seam;
        // hairline cracks along the grain
        double crack = Smooth((Fbm(s * 2.2 + k * 3.7, t * 95) - 0.74) / 0.05);
        r *= 1 - 0.5 * crack; g *= 1 - 0.5 * crack; b *= 1 - 0.5 * crack;
        // dirt / weathering blotches, darker and greener-brown
        double dirt = Smooth((Fbm(s * 2.3 + id * 5.1, t * 2.3 + id) - 0.45) / 0.35);
        r *= 1 - 0.42 * dirt; g *= 1 - 0.38 * dirt; b *= 1 - 0.30 * dirt;
        // pale worn patches
        double wear = Smooth((Fbm(s * 4.1 + id * 2.3, t * 4.1) - 0.66) / 0.1);
        r = Lerp(r, 0.62, 0.25 * wear); g = Lerp(g, 0.5, 0.25 * wear); b = Lerp(b, 0.36, 0.25 * wear);
    }

    static readonly V L1 = Norm(new V(-0.45, 0.85, 0.55));
    static readonly V L2 = Norm(new V(0.7, 0.25, -0.2));

    public static void Render(string dir) {
        var wr = new double[N * N]; var wg = new double[N * N]; var wb = new double[N * N]; var wa = new double[N * N];
        var mg = new double[N * N]; var ma = new double[N * N];
        var ids = new int[N * N];
        double inv = 1.0 / (SS * SS);
        for (int py = 0; py < N; py++) for (int px = 0; px < N; px++) {
            double sr = 0, sg = 0, sb = 0, sa = 0, sm = 0, smc = 0;
            for (int sy = 0; sy < SS; sy++) for (int sx = 0; sx < SS; sx++) {
                double fx = px + (sx + 0.5) / SS, fy = py + (sy + 0.5) / SS;
                double u = (fx - N / 2.0) / SCALE, v = -(fy - CY) / SCALE;
                V o = ToObj(new V(u, v, 10)), dv = ToObj(new V(0, 0, -1));
                double th; V n, p;
                int id = Cast(o, dv, out th, out n, out p);
                if (id == 0 || id == 5) continue;
                if (sx == SS / 2 && sy == SS / 2) ids[py * N + px] = id;
                double s, t; V ts, tt;
                Local(id, p, out s, out t, out ts, out tt);
                const double e = 0.010;
                double h0 = Height(id, s, t);
                double gs = (Height(id, s + e, t) - Height(id, s - e, t)) / (2 * e);
                double gt = (Height(id, s, t + e) - Height(id, s, t - e)) / (2 * e);
                V np = Norm(Add(n, Mul(Add(Mul(ts, gs), Mul(tt, gt)), -1.1)));
                const double aod = 0.045;
                double havg = (Height(id, s + aod, t) + Height(id, s - aod, t) + Height(id, s, t + aod) + Height(id, s, t - aod)) / 4;
                double ao = 1 - Clamp((havg - h0) * 13, 0, 0.7);
                double gm = Math.Sqrt(gs * gs + gt * gt);
                V view = new V(-dv.x, -dv.y, -dv.z);
                double diff1 = Math.Max(0, Dot(np, L1)), diff2 = Math.Max(0, Dot(np, L2));
                double amb = 0.34 + 0.20 * n.y;
                double fres = Math.Pow(1 - Clamp(Dot(n, view), 0, 1), 3) * 0.22;
                double light = (amb + 0.80 * diff1 + 0.22 * diff2) * ao + fres;
                V hv = Norm(Add(L1, view));
                double sp = Math.Pow(Math.Max(0, Dot(np, hv)), 38);
                double wr0, wg0, wb0; Wood(id, s, t, out wr0, out wg0, out wb0);
                double wl = light + sp * 0.05;
                // painted look: warm highlights, cool purple-ish shadows
                double cool = 1 - Clamp(wl, 0, 1);
                sr += wr0 * (wl * 1.05 + cool * 0.02); sg += wg0 * wl; sb += wb0 * (wl * 0.9 + cool * 0.16); sa += 1;
                if (MetalSd(id, s, t) > 0) {
                    double scr = VNoise(s * 38, t * 4 + id) * 0.5 + VNoise(s * 90, t * 9) * 0.3;
                    double bs = 0.78 + (scr - 0.4) * 0.30 + (Fbm(s * 3 + id, t * 3) - 0.5) * 0.30;
                    // rust / grime patches
                    double grime = Smooth((Fbm(s * 4.5 + id * 7.7, t * 4.5 + id * 1.3) - 0.5) / 0.22);
                    bs *= 1 - 0.50 * grime;
                    // dents: low-frequency dark pits
                    bs *= 1 - 0.25 * Smooth((VNoise(s * 22 + id, t * 22) - 0.78) / 0.12);
                    // worn, bright edges on the bevels that face the light
                    double edgeWear = Smooth((gm - 0.45) / 0.9) * Clamp(diff1 * 1.4, 0, 1);
                    sm += bs * (light * 0.95) + sp * 0.5 * (1 - 0.6 * grime) + 0.30 * edgeWear * (1 - 0.7 * grime); smc += 1;
                }
            }
            int i = py * N + px;
            if (sa > 0) { wr[i] = sr / sa; wg[i] = sg / sa; wb[i] = sb / sa; wa[i] = sa * inv; }
            if (smc > 0) { mg[i] = sm / smc; ma[i] = smc * inv; }
        }
        var wout = NewTga(); var mout = NewTga();
        for (int y = 0; y < N; y++) for (int x = 0; x < N; x++) {
            int i = y * N + x; double e2 = 1.0;
            if (wa[i] > 0) {
                int[,] nb = { { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 3, 3 }, { -3, 3 }, { 3, -3 }, { -3, -3 } };
                for (int k = 0; k < 8; k++) {
                    int nx = x + nb[k, 0], ny = y + nb[k, 1];
                    if (nx < 0 || ny < 0 || nx >= N || ny >= N) continue;
                    int j = ny * N + nx;
                    if (wa[j] < 0.5) e2 = Math.Min(e2, 0.18);
                    else if (ids[j] != ids[i] && ids[i] != 0 && ids[j] != 0) e2 = Math.Min(e2, 0.72);
                }
            }
            Put(wout, x, y, wr[i] * e2, wg[i] * e2, wb[i] * e2, wa[i]);
            if (ma[i] > 0) Put(mout, x, y, mg[i] * e2, mg[i] * e2, mg[i] * e2, ma[i]);
        }
        File.WriteAllBytes(Path.Combine(dir, "case_wood.tga"), wout);
        File.WriteAllBytes(Path.Combine(dir, "case_metal.tga"), mout);
    }
    static void Put(byte[] b, int x, int y, double r, double g, double bl, double a) {
        int i = 18 + (y * N + x) * 4;
        b[i] = (byte)(Clamp(bl, 0, 1) * 255); b[i + 1] = (byte)(Clamp(g, 0, 1) * 255);
        b[i + 2] = (byte)(Clamp(r, 0, 1) * 255); b[i + 3] = (byte)(Clamp(a, 0, 1) * 255);
    }
    static byte[] NewTga() {
        var b = new byte[18 + N * N * 4];
        b[2] = 2; b[12] = N & 255; b[13] = N >> 8; b[14] = N & 255; b[15] = N >> 8; b[16] = 32; b[17] = 0x28;
        return b;
    }
}
'@
}

New-Item -ItemType Directory -Force $Out | Out-Null
[CaseArt]::Render((Resolve-Path $Out).Path)
Get-ChildItem $Out -Filter case_*.tga | Select-Object Name, Length
