# Extract video frames via Media Foundation SourceReader (C# interop). No ffmpeg on this PC.
# Reads the video sequentially and saves one JPEG every -StepSec seconds (fNNN_<sec>s.jpg).
# usage: powershell -File tools/vidframes.ps1 -Video <file.mp4> -OutDir <dir> [-StepSec 1]
# Note: WinRT MediaComposition.GetThumbnailAsync does NOT work from PowerShell 5.1 (IVector.Add/Append fail); this does.
param([Parameter(Mandatory=$true)][string]$Video,
      [Parameter(Mandatory=$true)][string]$OutDir,
      [double]$StepSec = 2.0)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$src = @'
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;

namespace MFX {
  [StructLayout(LayoutKind.Explicit, Size = 24)]
  public struct PropVariant {
    [FieldOffset(0)] public ushort vt;
    [FieldOffset(8)] public long hVal;
    [FieldOffset(8)] public ulong uhVal;
  }
  [ComImport, Guid("2cd2d921-c447-44a7-a13c-4adabfc247e3"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IMFAttributes {
    void GetItem(ref Guid k, IntPtr v); void GetItemType(ref Guid k, out int t); void CompareItem(ref Guid k, IntPtr v, out bool r);
    void Compare(IMFAttributes o, int t, out bool r); void GetUINT32(ref Guid k, out uint v); void GetUINT64(ref Guid k, out ulong v);
    void GetDouble(ref Guid k, out double v); void GetGUID(ref Guid k, out Guid v); void GetStringLength(ref Guid k, out uint l);
    void GetString(ref Guid k, IntPtr s, uint n, IntPtr l); void GetAllocatedString(ref Guid k, out IntPtr s, out uint l);
    void GetBlobSize(ref Guid k, out uint n); void GetBlob(ref Guid k, IntPtr b, uint n, IntPtr l); void GetAllocatedBlob(ref Guid k, out IntPtr b, out uint n);
    void GetUnknown(ref Guid k, ref Guid iid, out IntPtr p); void SetItem(ref Guid k, IntPtr v); void DeleteItem(ref Guid k); void DeleteAllItems();
    void SetUINT32(ref Guid k, uint v); void SetUINT64(ref Guid k, ulong v); void SetDouble(ref Guid k, double v); void SetGUID(ref Guid k, ref Guid v);
    void SetString(ref Guid k, [MarshalAs(UnmanagedType.LPWStr)] string s); void SetBlob(ref Guid k, IntPtr b, uint n); void SetUnknown(ref Guid k, IntPtr p);
    void LockStore(); void UnlockStore(); void GetCount(out uint n); void GetItemByIndex(uint i, out Guid k, IntPtr v); void CopyAllItems(IMFAttributes d);
  }
  [ComImport, Guid("44ae0fa8-ea31-4109-8d2e-4cae4997c555"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IMFMediaType {
    void GetItem(ref Guid k, IntPtr v); void GetItemType(ref Guid k, out int t); void CompareItem(ref Guid k, IntPtr v, out bool r);
    void Compare(IMFAttributes o, int t, out bool r); void GetUINT32(ref Guid k, out uint v); void GetUINT64(ref Guid k, out ulong v);
    void GetDouble(ref Guid k, out double v); void GetGUID(ref Guid k, out Guid v); void GetStringLength(ref Guid k, out uint l);
    void GetString(ref Guid k, IntPtr s, uint n, IntPtr l); void GetAllocatedString(ref Guid k, out IntPtr s, out uint l);
    void GetBlobSize(ref Guid k, out uint n); void GetBlob(ref Guid k, IntPtr b, uint n, IntPtr l); void GetAllocatedBlob(ref Guid k, out IntPtr b, out uint n);
    void GetUnknown(ref Guid k, ref Guid iid, out IntPtr p); void SetItem(ref Guid k, IntPtr v); void DeleteItem(ref Guid k); void DeleteAllItems();
    void SetUINT32(ref Guid k, uint v); void SetUINT64(ref Guid k, ulong v); void SetDouble(ref Guid k, double v); void SetGUID(ref Guid k, ref Guid v);
    void SetString(ref Guid k, [MarshalAs(UnmanagedType.LPWStr)] string s); void SetBlob(ref Guid k, IntPtr b, uint n); void SetUnknown(ref Guid k, IntPtr p);
    void LockStore(); void UnlockStore(); void GetCount(out uint n); void GetItemByIndex(uint i, out Guid k, IntPtr v); void CopyAllItems(IMFAttributes d);
    void GetMajorType(out Guid g); void IsCompressedFormat(out bool b); void IsEqual(IMFMediaType t, out uint f); void GetRepresentation(Guid g, out IntPtr p); void FreeRepresentation(Guid g, IntPtr p);
  }
  [ComImport, Guid("045fa593-8799-42b8-bc8d-8968c6453507"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IMFMediaBuffer {
    void Lock(out IntPtr p, out uint max, out uint cur); void Unlock(); void GetCurrentLength(out uint n); void SetCurrentLength(uint n); void GetMaxLength(out uint n);
  }
  [ComImport, Guid("c40a00f2-b93a-4d80-ae8c-5a1c634f58e4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IMFSample {
    void GetItem(ref Guid k, IntPtr v); void GetItemType(ref Guid k, out int t); void CompareItem(ref Guid k, IntPtr v, out bool r);
    void Compare(IMFAttributes o, int t, out bool r); void GetUINT32(ref Guid k, out uint v); void GetUINT64(ref Guid k, out ulong v);
    void GetDouble(ref Guid k, out double v); void GetGUID(ref Guid k, out Guid v); void GetStringLength(ref Guid k, out uint l);
    void GetString(ref Guid k, IntPtr s, uint n, IntPtr l); void GetAllocatedString(ref Guid k, out IntPtr s, out uint l);
    void GetBlobSize(ref Guid k, out uint n); void GetBlob(ref Guid k, IntPtr b, uint n, IntPtr l); void GetAllocatedBlob(ref Guid k, out IntPtr b, out uint n);
    void GetUnknown(ref Guid k, ref Guid iid, out IntPtr p); void SetItem(ref Guid k, IntPtr v); void DeleteItem(ref Guid k); void DeleteAllItems();
    void SetUINT32(ref Guid k, uint v); void SetUINT64(ref Guid k, ulong v); void SetDouble(ref Guid k, double v); void SetGUID(ref Guid k, ref Guid v);
    void SetString(ref Guid k, [MarshalAs(UnmanagedType.LPWStr)] string s); void SetBlob(ref Guid k, IntPtr b, uint n); void SetUnknown(ref Guid k, IntPtr p);
    void LockStore(); void UnlockStore(); void GetCount(out uint n); void GetItemByIndex(uint i, out Guid k, IntPtr v); void CopyAllItems(IMFAttributes d);
    void GetSampleFlags(out uint f); void SetSampleFlags(uint f); void GetSampleTime(out long t); void SetSampleTime(long t); void GetSampleDuration(out long d); void SetSampleDuration(long d);
    void GetBufferCount(out uint n); void GetBufferByIndex(uint i, out IMFMediaBuffer b); void ConvertToContiguousBuffer(out IMFMediaBuffer b); void AddBuffer(IMFMediaBuffer b);
    void RemoveBufferByIndex(uint i); void RemoveAllBuffers(); void GetTotalLength(out uint n); void CopyToBuffer(IMFMediaBuffer b);
  }
  [ComImport, Guid("70ae66f2-c809-4e4f-8915-bdcb406b7993"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IMFSourceReader {
    void GetStreamSelection(uint i, out bool s); void SetStreamSelection(uint i, bool s);
    void GetNativeMediaType(uint i, uint j, out IMFMediaType t); void GetCurrentMediaType(uint i, out IMFMediaType t);
    void SetCurrentMediaType(uint i, IntPtr r, IMFMediaType t); void SetCurrentPosition(ref Guid f, ref PropVariant p);
    void ReadSample(uint i, uint f, out uint ai, out uint fl, out long ts, out IMFSample s); void Flush(uint i);
    void GetServiceForStream(uint i, ref Guid svc, ref Guid iid, out IntPtr p); void GetPresentationAttribute(uint i, ref Guid k, out PropVariant v);
  }
  public static class MF {
    [DllImport("mfplat.dll")] public static extern int MFStartup(uint v, uint f);
    [DllImport("mfplat.dll")] public static extern int MFCreateAttributes(out IMFAttributes a, uint n);
    [DllImport("mfplat.dll")] public static extern int MFCreateMediaType(out IMFMediaType t);
    [DllImport("mfreadwrite.dll")] public static extern int MFCreateSourceReaderFromURL([MarshalAs(UnmanagedType.LPWStr)] string url, IMFAttributes a, out IMFSourceReader r);
    public static Guid MF_MT_MAJOR_TYPE = new Guid("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
    public static Guid MF_MT_SUBTYPE = new Guid("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
    public static Guid MF_MT_FRAME_SIZE = new Guid("1652c33d-d6b2-4012-b834-72030849a37d");
    public static Guid MF_MT_DEFAULT_STRIDE = new Guid("644b4e48-1e02-4516-b0eb-c01ca9d49ac6");
    public static Guid MFMediaType_Video = new Guid("73646976-0000-0010-8000-00aa00389b71");
    public static Guid MFVideoFormat_RGB32 = new Guid("00000016-0000-0010-8000-00aa00389b71");
    public static Guid MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING = new Guid("fb394f3d-ccf1-42ee-bbb3-f9b845d5681d");
    public static Guid MF_PD_DURATION = new Guid("6c990d33-bb8e-477a-8598-0d5d96fcd88a");
    public static Guid GUID_NULL = Guid.Empty;
    public const uint FIRST_VIDEO = 0xFFFFFFFC; public const uint ALL = 0xFFFFFFFE; public const uint MEDIASOURCE = 0xFFFFFFFF;

    public static string Extract(string path, string outDir, double step) {
      MFStartup(0x00020070, 0);
      IMFAttributes attr; MFCreateAttributes(out attr, 2);
      attr.SetUINT32(ref MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, 1);
      IMFSourceReader rd; int hr = MFCreateSourceReaderFromURL(path, attr, out rd);
      if (hr != 0) return "create failed " + hr.ToString("X");
      rd.SetStreamSelection(ALL, false); rd.SetStreamSelection(FIRST_VIDEO, true);
      IMFMediaType mt; MFCreateMediaType(out mt);
      mt.SetGUID(ref MF_MT_MAJOR_TYPE, ref MFMediaType_Video); mt.SetGUID(ref MF_MT_SUBTYPE, ref MFVideoFormat_RGB32);
      rd.SetCurrentMediaType(FIRST_VIDEO, IntPtr.Zero, mt);
      IMFMediaType cur; rd.GetCurrentMediaType(FIRST_VIDEO, out cur);
      ulong fs; cur.GetUINT64(ref MF_MT_FRAME_SIZE, out fs);
      int w = (int)(fs >> 32), h = (int)(fs & 0xFFFFFFFF);
      int stride = w * 4; try { uint s; cur.GetUINT32(ref MF_MT_DEFAULT_STRIDE, out s); stride = (int)s; } catch {}
      PropVariant dur; rd.GetPresentationAttribute(MEDIASOURCE, ref MF_PD_DURATION, out dur);
      double durSec = dur.uhVal / 1e7;
      System.IO.Directory.CreateDirectory(outDir);
      int n = 0; double nextT = 0;
      while (true) {
        IMFSample smp = null; uint ai, fl; long ts;
        rd.ReadSample(FIRST_VIDEO, 0, out ai, out fl, out ts, out smp);
        if ((fl & 2) != 0) break;
        if (smp == null) continue;
        double t = ts / 1e7;
        if (t + 0.001 < nextT) { Marshal.ReleaseComObject(smp); continue; }
        nextT = Math.Floor(t / step) * step + step;
        IMFMediaBuffer buf; smp.ConvertToContiguousBuffer(out buf);
        IntPtr p; uint mx, cl; buf.Lock(out p, out mx, out cl);
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppRgb);
        BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppRgb);
        byte[] row = new byte[w * 4];
        int absStride = Math.Abs(stride);
        for (int y = 0; y < h; y++) {
          int srcY = stride < 0 ? (h - 1 - y) : y;
          Marshal.Copy(new IntPtr(p.ToInt64() + (long)srcY * absStride), row, 0, w * 4);
          Marshal.Copy(row, 0, new IntPtr(bd.Scan0.ToInt64() + (long)y * bd.Stride), w * 4);
        }
        bmp.UnlockBits(bd); buf.Unlock();
        string name = System.IO.Path.Combine(outDir, string.Format("f{0:D3}_{1:000.0}s.jpg", n, t));
        bmp.Save(name, ImageFormat.Jpeg); bmp.Dispose();
        Marshal.ReleaseComObject(buf); Marshal.ReleaseComObject(smp);
        n++;
      }
      return string.Format("size={0}x{1} stride={2} duration={3:F1}s frames={4}", w, h, stride, durSec, n);
    }
  }
}
'@
Add-Type -TypeDefinition $src -ReferencedAssemblies System.Drawing
[MFX.MF]::Extract((Resolve-Path -LiteralPath $Video).Path, $OutDir, $StepSec)
