param(
    [int]$GamePID   = 0,
    [string]$StateFile = ""
)

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AudioMonitor {

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"),
 ClassInterface(ClassInterfaceType.None)]
public class MMDeviceEnumerator {}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string pwstrId, out IMMDevice ppDevice);
    int RegisterEndpointNotificationCallback(IntPtr pClient);
    int UnregisterEndpointNotificationCallback(IntPtr pClient);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid iid, uint dwClsCtx, IntPtr pActivationParams,
                 [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    int OpenPropertyStore(uint stgmAccess, out IntPtr ppProperties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
    int GetState(out int pdwState);
}

[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionManager2 {
    int GetAudioSessionControl(IntPtr sessionGuid, uint streamFlags, out IntPtr ctrl);
    int GetSimpleAudioVolume(IntPtr sessionGuid, uint streamFlags, out IntPtr vol);
    int GetSessionEnumerator(out IAudioSessionEnumerator ppSessionEnum);
    int RegisterSessionNotification(IntPtr pNotify);
    int UnregisterSessionNotification(IntPtr pNotify);
    int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionID, IntPtr pDuck);
    int UnregisterDuckNotification(IntPtr pDuck);
}

[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionEnumerator {
    int GetCount(out int SessionCount);
    int GetSession(int SessionIndex, out IAudioSessionControl Session);
}

// vtable: IUnknown(3) + 9 IAudioSessionControl methods
[Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionControl {
    int GetState(out int pRetVal);
    int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string val, ref Guid ctx);
    int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string val, ref Guid ctx);
    int GetGroupingParam(out Guid pRetVal);
    int SetGroupingParam(ref Guid ovr, ref Guid ctx);
    int RegisterAudioSessionNotification(IntPtr pNotify);
    int UnregisterAudioSessionNotification(IntPtr pNotify);
}

// vtable: IUnknown(3) + 9 inherited + 5 own  ==> list all 14 flat
[Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionControl2 {
    int GetState(out int pRetVal);
    int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string val, ref Guid ctx);
    int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string val, ref Guid ctx);
    int GetGroupingParam(out Guid pRetVal);
    int SetGroupingParam(ref Guid ovr, ref Guid ctx);
    int RegisterAudioSessionNotification(IntPtr pNotify);
    int UnregisterAudioSessionNotification(IntPtr pNotify);
    // IAudioSessionControl2-specific:
    int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int GetProcessId(out uint pRetVal);
    int IsSystemSoundsSession();
    int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
}

public static class Checker {
    private static readonly Guid IID_SessionManager2 =
        new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");

    public static bool HasOtherActiveSessions(int gamePid) {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
            IMMDevice device;
            // eRender=0, eMultimedia=1
            if (enumerator.GetDefaultAudioEndpoint(0, 1, out device) != 0)
                return false;

            Guid smGuid = IID_SessionManager2;
            object smObj;
            if (device.Activate(ref smGuid, 23 /*CLSCTX_ALL*/, IntPtr.Zero, out smObj) != 0)
                return false;

            var mgr = (IAudioSessionManager2)smObj;
            IAudioSessionEnumerator sessionEnum;
            if (mgr.GetSessionEnumerator(out sessionEnum) != 0)
                return false;

            int count;
            sessionEnum.GetCount(out count);

            for (int i = 0; i < count; i++) {
                try {
                    IAudioSessionControl ctrl;
                    if (sessionEnum.GetSession(i, out ctrl) != 0) continue;

                    int state;
                    if (ctrl.GetState(out state) != 0) continue;
                    if (state != 1) continue; // AudioSessionStateActive = 1

                    // QI: cast to IAudioSessionControl2 to read the PID.
                    // COM interop cast triggers QueryInterface on the underlying object.
                    var ctrl2 = (IAudioSessionControl2)ctrl;
                    uint pid;
                    if (ctrl2.GetProcessId(out pid) != 0) continue;
                    if (pid == 0) continue; // system/svchost sessions
                    if ((int)pid == gamePid) continue; // our own session

                    return true; // another app is actively playing audio
                } catch { }
            }
            return false;
        } catch {
            return false;
        }
    }
}

} // namespace AudioMonitor
'@

$lastState = ""

while ($true) {
    try {
        $active = [AudioMonitor.Checker]::HasOtherActiveSessions($GamePID)
        $state  = if ($active) { "MUTE" } else { "UNMUTE" }

        if ($state -ne $lastState) {
            $lastState = $state
            if ($StateFile -ne "") {
                [System.IO.File]::WriteAllText($StateFile, $state)
            }
        }
    } catch { }

    Start-Sleep -Milliseconds 500
}
