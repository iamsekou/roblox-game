// Lobby bubble portraits: cut the character out of a reference image, crop head-and-shoulders,
// give it a white "sticker" outline, and place it on a sunburst bubble. Output: 512x512 PNG with a
// transparent outside, ready to upload as a Roblox image.
// Silhouette style (owner, 2026-09-23): the figure is filled with a flat shadow colour, so only its
// outline shows - recognisable, but not coloured in.
// Compiled on the fly by make-portraits.ps1 (Windows PowerShell 5.1 => C# 5 syntax only).
using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

public static class PortraitMaker
{
    const int S = 512;          // output size
    const int MARGIN = 48;      // extra canvas around the crop so outlines never form along the crop edge
    const float OUTLINE = 11f;  // white sticker outline, px
    const float RIM = 3f;       // thin dark line outside the white outline, px
    static readonly double[] SHADOW = { 22, 24, 38 }; // silhouette fill (R, G, B)

    static byte[] Load(string path, out int w, out int h)
    {
        using (FileStream fs = File.OpenRead(path))
        {
            BitmapDecoder dec = BitmapDecoder.Create(fs, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            FormatConvertedBitmap conv = new FormatConvertedBitmap(dec.Frames[0], PixelFormats.Bgra32, null, 0);
            w = conv.PixelWidth;
            h = conv.PixelHeight;
            byte[] px = new byte[w * h * 4];
            conv.CopyPixels(px, w * 4, 0);
            return px;
        }
    }

    static void Save(string path, byte[] bgra, int w, int h)
    {
        BitmapSource src = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, bgra, w * 4);
        PngBitmapEncoder enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(src));
        using (FileStream fs = File.Create(path)) { enc.Save(fs); }
    }

    // Two-pass chamfer distance to the nearest pixel in `set` (0 on the set itself).
    static float[] DistanceTo(bool[] set, int w, int h)
    {
        const float A = 1f, B = 1.41421356f, INF = 1e9f;
        float[] d = new float[w * h];
        for (int i = 0; i < d.Length; i++) d[i] = set[i] ? 0f : INF;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = y * w + x; float v = d[i];
                if (x > 0) v = Math.Min(v, d[i - 1] + A);
                if (y > 0)
                {
                    v = Math.Min(v, d[i - w] + A);
                    if (x > 0) v = Math.Min(v, d[i - w - 1] + B);
                    if (x < w - 1) v = Math.Min(v, d[i - w + 1] + B);
                }
                d[i] = v;
            }
        for (int y = h - 1; y >= 0; y--)
            for (int x = w - 1; x >= 0; x--)
            {
                int i = y * w + x; float v = d[i];
                if (x < w - 1) v = Math.Min(v, d[i + 1] + A);
                if (y < h - 1)
                {
                    v = Math.Min(v, d[i + w] + A);
                    if (x < w - 1) v = Math.Min(v, d[i + w + 1] + B);
                    if (x > 0) v = Math.Min(v, d[i + w - 1] + B);
                }
                d[i] = v;
            }
        return d;
    }

    // Opaque images (JPG on a flat background): everything reachable from the border through
    // background-coloured pixels is background. Thin line art that the fill leaks along is
    // restored afterwards by a morphological close.
    static bool[] FigureFromFlatBackground(byte[] px, int w, int h, int tolerance, float closeRadius)
    {
        int rb = px[2], gb = px[1], bb = px[0];
        bool[] bg = new bool[w * h];
        Stack<int> stack = new Stack<int>();
        for (int x = 0; x < w; x++) { stack.Push(x); stack.Push((h - 1) * w + x); }
        for (int y = 0; y < h; y++) { stack.Push(y * w); stack.Push(y * w + w - 1); }
        while (stack.Count > 0)
        {
            int i = stack.Pop();
            if (bg[i]) continue;
            int o = i * 4;
            if (Math.Abs(px[o + 2] - rb) > tolerance || Math.Abs(px[o + 1] - gb) > tolerance || Math.Abs(px[o] - bb) > tolerance) continue;
            bg[i] = true;
            int x = i % w, y = i / w;
            if (x > 0) stack.Push(i - 1);
            if (x < w - 1) stack.Push(i + 1);
            if (y > 0) stack.Push(i - w);
            if (y < h - 1) stack.Push(i + w);
        }
        bool[] fig = new bool[w * h];
        for (int i = 0; i < fig.Length; i++) fig[i] = !bg[i];
        // close = dilate then erode
        float[] d1 = DistanceTo(fig, w, h);
        bool[] notDilated = new bool[w * h];
        for (int i = 0; i < fig.Length; i++) notDilated[i] = d1[i] > closeRadius;
        float[] d2 = DistanceTo(notDilated, w, h);
        for (int i = 0; i < fig.Length; i++) fig[i] = d2[i] > closeRadius;
        return fig;
    }

    static void KeepComponent(byte[] alpha, int w, int h, int sx, int sy)
    {
        bool[] keep = new bool[w * h];
        Stack<int> stack = new Stack<int>();
        stack.Push(sy * w + sx);
        while (stack.Count > 0)
        {
            int i = stack.Pop();
            if (keep[i] || alpha[i] < 128) continue;
            keep[i] = true;
            int x = i % w, y = i / w;
            if (x > 0) stack.Push(i - 1);
            if (x < w - 1) stack.Push(i + 1);
            if (y > 0) stack.Push(i - w);
            if (y < h - 1) stack.Push(i + w);
        }
        for (int i = 0; i < alpha.Length; i++) if (!keep[i]) alpha[i] = 0;
    }

    // A red upholstered chair behind the figure (L): drop the red, and drop the white frame, which is
    // the only light-grey material lying between the background and the red within `reach` px.
    static void DropChair(byte[] px, byte[] alpha, int w, int h, float reach)
    {
        bool[] background = new bool[w * h], red = new bool[w * h];
        for (int i = 0; i < w * h; i++)
        {
            int r = px[i * 4 + 2], g = px[i * 4 + 1], b = px[i * 4];
            background[i] = alpha[i] < 128;
            red[i] = r > 90 && r > 2 * g && r > 2 * b;
        }
        float[] toBackground = DistanceTo(background, w, h);
        float[] toRed = DistanceTo(red, w, h);
        for (int i = 0; i < w * h; i++)
        {
            int r = px[i * 4 + 2], g = px[i * 4 + 1], b = px[i * 4];
            int lo = Math.Min(r, Math.Min(g, b)), hi = Math.Max(r, Math.Max(g, b));
            bool frame = lo > 120 && hi - lo < 60 && toBackground[i] <= reach && toRed[i] <= reach;
            if (red[i] || frame) alpha[i] = 0;
        }
        Open(alpha, w, h, 3f); // the frame's thin ink lines survive the colour test
    }

    // Morphological opening (erode, then dilate by r): erases anything thinner than about 2r px, such
    // as stray ink lines or a single hair strand, while leaving the body's shape alone.
    static void Open(byte[] alpha, int w, int h, float r)
    {
        bool[] empty = new bool[w * h];
        for (int i = 0; i < empty.Length; i++) empty[i] = alpha[i] < 128;
        float[] toEmpty = DistanceTo(empty, w, h);
        bool[] eroded = new bool[w * h];
        for (int i = 0; i < eroded.Length; i++) eroded[i] = toEmpty[i] > r;
        float[] toEroded = DistanceTo(eroded, w, h);
        for (int i = 0; i < alpha.Length; i++) alpha[i] = toEroded[i] <= r ? (byte)255 : (byte)0;
    }

    // Any empty region not reachable from the image border becomes solid.
    static void FillHoles(byte[] alpha, int w, int h)
    {
        bool[] outside = new bool[w * h];
        Stack<int> stack = new Stack<int>();
        for (int x = 0; x < w; x++) { stack.Push(x); stack.Push((h - 1) * w + x); }
        for (int y = 0; y < h; y++) { stack.Push(y * w); stack.Push(y * w + w - 1); }
        while (stack.Count > 0)
        {
            int i = stack.Pop();
            if (outside[i] || alpha[i] >= 128) continue;
            outside[i] = true;
            int x = i % w, y = i / w;
            if (x > 0) stack.Push(i - 1);
            if (x < w - 1) stack.Push(i + 1);
            if (y > 0) stack.Push(i - w);
            if (y < h - 1) stack.Push(i + w);
        }
        for (int i = 0; i < alpha.Length; i++) if (!outside[i]) alpha[i] = 255;
    }

    static double Clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
    static double Lerp(double a, double b, double t) { return a + (b - a) * t; }

    // tolerance: how far from the background colour a pixel may be and still count as background
    // (lower it when dark hair or clothing touches a black background). closeRadius: how thick a
    // line-art channel the clean-up may refill.
    public static void Render(string input, string output, int cropX, int cropY, int side,
                              byte r1, byte g1, byte b1, byte r2, byte g2, byte b2,
                              int tolerance, float closeRadius, bool silhouette,
                              bool dropChair, int seedX, int seedY, float cleanRadius)
    {
        int w, h;
        byte[] px = Load(input, out w, out h);
        bool hasAlpha = px[3] < 250 || px[(w * h - 1) * 4 + 3] < 250;
        byte[] alpha = new byte[w * h];
        if (hasAlpha)
        {
            for (int i = 0; i < w * h; i++) alpha[i] = px[i * 4 + 3];
        }
        else
        {
            bool[] fig = FigureFromFlatBackground(px, w, h, tolerance, closeRadius);
            for (int i = 0; i < w * h; i++) alpha[i] = fig[i] ? (byte)255 : (byte)0;
        }
        // Props that merge with the figure (L's armchair): drop them, then keep only the piece
        // connected to the seed point (e.g. the face).
        if (dropChair) DropChair(px, alpha, w, h, 30f);
        if (cleanRadius > 0) Open(alpha, w, h, cleanRadius); // e.g. Goku's single hair strand
        if (seedX >= 0 && seedY >= 0)
        {
            KeepComponent(alpha, w, h, seedX, seedY);
            FillHoles(alpha, w, h); // a silhouette has no see-through gaps inside it
        }

        // Resample the crop (+margin) into a premultiplied float canvas, bilinear + supersampling.
        int C = S + 2 * MARGIN;
        double k = (double)side / S;
        int n = Math.Max(2, Math.Min(6, (int)Math.Ceiling(k * 2)));
        float[] cr = new float[C * C], cg = new float[C * C], cb = new float[C * C], ca = new float[C * C];
        for (int v = 0; v < C; v++)
            for (int u = 0; u < C; u++)
            {
                double sr = 0, sg = 0, sb = 0, sa = 0;
                for (int j = 0; j < n; j++)
                    for (int i2 = 0; i2 < n; i2++)
                    {
                        double sx = cropX + (u - MARGIN + (i2 + 0.5) / n) * k - 0.5;
                        double sy = cropY + (v - MARGIN + (j + 0.5) / n) * k - 0.5;
                        int x0 = (int)Math.Floor(sx), y0 = (int)Math.Floor(sy);
                        double fx = sx - x0, fy = sy - y0;
                        for (int t = 0; t < 4; t++)
                        {
                            int xx = x0 + (t & 1), yy = y0 + (t >> 1);
                            double wgt = ((t & 1) == 1 ? fx : 1 - fx) * ((t >> 1) == 1 ? fy : 1 - fy);
                            if (wgt <= 0 || xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
                            int p = yy * w + xx;
                            double a = alpha[p] / 255.0 * wgt;
                            sr += px[p * 4 + 2] * a; sg += px[p * 4 + 1] * a; sb += px[p * 4] * a; sa += a;
                        }
                    }
                int q = v * C + u;
                double inv = 1.0 / (n * n);
                cr[q] = (float)(sr * inv); cg[q] = (float)(sg * inv); cb[q] = (float)(sb * inv); ca[q] = (float)(sa * inv);
            }

        bool[] solid = new bool[C * C];
        for (int i = 0; i < solid.Length; i++) solid[i] = ca[i] > 0.5f;
        float[] dist = DistanceTo(solid, C, C);

        byte[] outPx = new byte[S * S * 4];
        double R = S / 2.0 - 3, cx = S / 2.0, cy = S / 2.0;
        for (int y = 0; y < S; y++)
            for (int x = 0; x < S; x++)
            {
                double dx = x + 0.5 - cx, dy = y + 0.5 - cy, r = Math.Sqrt(dx * dx + dy * dy);
                double t = Math.Pow(Clamp01(r / R), 1.3);
                double ang = Math.Atan2(dy, dx);
                double ray = Math.Sin(ang * 14) > 0.35 ? 0.10 * (1 - t * 0.5) : 0; // sunburst
                double R_ = Lerp(r1, r2, t), G_ = Lerp(g1, g2, t), B_ = Lerp(b1, b2, t);
                R_ += (255 - R_) * ray; G_ += (255 - G_) * ray; B_ += (255 - B_) * ray;

                int q = (y + MARGIN) * C + (x + MARGIN);
                double d = dist[q];
                double rimA = Clamp01(OUTLINE + RIM - d + 0.5);
                R_ = Lerp(R_, 28, rimA); G_ = Lerp(G_, 28, rimA); B_ = Lerp(B_, 36, rimA);
                double whiteA = Clamp01(OUTLINE - d + 0.5);
                R_ = Lerp(R_, 255, whiteA); G_ = Lerp(G_, 255, whiteA); B_ = Lerp(B_, 255, whiteA);

                double fa = ca[q];
                if (silhouette)
                {
                    R_ = SHADOW[0] * fa + R_ * (1 - fa); G_ = SHADOW[1] * fa + G_ * (1 - fa); B_ = SHADOW[2] * fa + B_ * (1 - fa);
                }
                else
                {
                    R_ = cr[q] + R_ * (1 - fa); G_ = cg[q] + G_ * (1 - fa); B_ = cb[q] + B_ * (1 - fa);
                }

                // bubble ring: dark hairline inside a white band
                double band = Clamp01(r - (R - 9) + 0.5);
                double hair = Clamp01(r - (R - 12) + 0.5) * (1 - band);
                R_ = Lerp(R_, 28, hair); G_ = Lerp(G_, 28, hair); B_ = Lerp(B_, 36, hair);
                R_ = Lerp(R_, 255, band); G_ = Lerp(G_, 255, band); B_ = Lerp(B_, 255, band);

                double circleA = Clamp01(R + 0.5 - r);
                int o = (y * S + x) * 4;
                outPx[o] = (byte)Math.Max(0, Math.Min(255, B_));
                outPx[o + 1] = (byte)Math.Max(0, Math.Min(255, G_));
                outPx[o + 2] = (byte)Math.Max(0, Math.Min(255, R_));
                outPx[o + 3] = (byte)(circleA * 255);
            }
        Save(output, outPx, S, S);
    }

    // Grid of finished portraits on a mid-grey backdrop, for quick review.
    public static void ContactSheet(string[] files, string output, int columns)
    {
        const int cell = 256;
        int rows = (files.Length + columns - 1) / columns;
        int W = columns * cell, H = rows * cell;
        byte[] sheet = new byte[W * H * 4];
        for (int i = 0; i < W * H; i++) { sheet[i * 4] = 70; sheet[i * 4 + 1] = 70; sheet[i * 4 + 2] = 70; sheet[i * 4 + 3] = 255; }
        for (int f = 0; f < files.Length; f++)
        {
            int w, h;
            byte[] px = Load(files[f], out w, out h);
            int ox = (f % columns) * cell, oy = (f / columns) * cell;
            for (int y = 0; y < cell; y++)
                for (int x = 0; x < cell; x++)
                {
                    int sx = x * w / cell, sy = y * h / cell;
                    int s = (sy * w + sx) * 4, dIdx = ((oy + y) * W + ox + x) * 4;
                    double a = px[s + 3] / 255.0;
                    for (int c = 0; c < 3; c++) sheet[dIdx + c] = (byte)(px[s + c] * a + sheet[dIdx + c] * (1 - a));
                }
        }
        Save(output, sheet, W, H);
    }
}
