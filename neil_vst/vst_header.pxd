#
from libc.stdint cimport int64_t, int32_t


cdef extern from "windows.h":
    pass


cdef extern from "libloaderapi.h":

    ctypedef void* PVOID
    ctypedef PVOID HANDLE
    ctypedef HANDLE HINSTANCE
    ctypedef HINSTANCE HMODULE

    ctypedef unsigned long DWORD
    ctypedef char CHAR
    ctypedef CHAR*LPCSTR

    HMODULE LoadLibraryExA(LPCSTR lpLibFileName, HANDLE hFile, DWORD  dwFlags)
    HMODULE LoadLibraryA(LPCSTR lpLibFileName)
    DWORD GetLastError()

    ctypedef void*(*FARPROC)()
    FARPROC GetProcAddress(HMODULE hModule, LPCSTR  lpProcName);


cdef extern from "aeffectx.h":

    ctypedef int32_t VstInt32
    ctypedef int64_t VstIntPtr

    cdef enum AudioMasterOpcodes:
        audioMasterAutomate = 0
        audioMasterVersion = 1
        audioMasterCurrentId = 2
        audioMasterIdle = 3
        audioMasterPinConnected = 4
        audioMasterWantMidi = 6
        audioMasterGetTime = 7
        audioMasterProcessEvents = 8
        audioMasterIOChanged = 13
        audioMasterSizeWindow = 15
        audioMasterGetSampleRate = 16
        audioMasterGetBlockSize = 17
        audioMasterGetInputLatency = 18
        audioMasterGetOutputLatency = 19
        audioMasterGetCurrentProcessLevel = 23
        audioMasterGetAutomationState = 24
        audioMasterOfflineStart = 25
        audioMasterOfflineRead = 26
        audioMasterOfflineWrite = 27
        audioMasterOfflineGetCurrentPass = 28
        audioMasterOfflineGetCurrentMetaPass = 29
        audioMasterGetVendorString = 32
        audioMasterGetProductString = 33
        audioMasterGetVendorVersion = 34
        audioMasterVendorSpecific = 35
        audioMasterCanDo = 37
        audioMasterGetLanguage = 38
        audioMasterGetDirectory = 41
        audioMasterUpdateDisplay = 42
        audioMasterBeginEdit = 43
        audioMasterEndEdit = 44
        audioMasterOpenFileSelector = 45
        audioMasterCloseFileSelector = 46

    cdef enum AEffectOpcodes:
        effOpen = 0
        effClose = 1
        effSetProgram = 2
        effGetProgram = 3
        effSetProgramName = 4
        effGetProgramName = 5
        effGetParamLabel = 6
        effGetParamDisplay = 7
        effGetParamName = 8
        effSetSampleRate = 10
        effSetBlockSize = 11
        effMainsChanged = 12
        effEditGetRect = 13
        effEditOpen = 14
        effEditClose = 15
        effEditDraw = 16
        effEditMouse = 17
        effEditKey = 18
        effEditIdle = 19
        effEditTop = 20
        effEditSleep = 21
        effIdentify = 22
        effGetChunk = 23
        effSetChunk = 24
        effNumOpcodes = 25

    cdef enum AEffectXOpcodes:
        effProcessEvents = 25
        effCanBeAutomated = 26
        effString2Parameter = 27
        effGetProgramNameIndexed = 29
        effGetInputProperties = 33
        effGetOutputProperties = 34
        effGetPlugCategory = 35
        effOfflineNotify = 38
        effOfflinePrepare = 39
        effOfflineRun = 40
        effProcessVarIo = 41
        effSetSpeakerArrangement = 42
        effSetBypass = 44
        effGetEffectName = 45
        effGetVendorString = 47
        effGetProductString = 48
        effGetVendorVersion = 49
        effVendorSpecific = 50
        effCanDo = 51
        effGetTailSize = 52
        effGetParameterProperties = 56
        effGetVstVersion = 58
        effEditKeyDown = 59
        effEditKeyUp = 60
        effSetEditKnobMode = 61
        effGetMidiProgramName = 62
        effGetCurrentMidiProgram = 63
        effGetMidiProgramCategory = 64
        effHasMidiProgramsChanged = 65
        effGetMidiKeyName = 66
        effBeginSetProgram = 67
        effEndSetProgram = 68
        effGetSpeakerArrangement = 69
        effShellGetNextPlugin = 70
        effStartProcess = 71
        effStopProcess = 72
        effSetTotalSampleToProcess = 73
        effSetPanLaw = 74
        effBeginLoadBank = 75
        effBeginLoadProgram = 76
        effSetProcessPrecision = 77
        effGetNumMidiInputChannels = 78
        effGetNumMidiOutputChannels = 79

    ctypedef struct VstEvent:
        VstInt32 type
        VstInt32 byteSize
        VstInt32 deltaFrames
        VstInt32 flags
        char data[16]

    cdef struct VstEvents:
        VstInt32 numEvents
        VstIntPtr reserved
        VstEvent*events[2]

    cdef struct VstEvents1024:
        VstInt32 numEvents
        VstIntPtr reserved
        VstEvent*events[1024]

    cdef struct VstEvents16:
        VstInt32 numEvents
        VstIntPtr reserved
        VstEvent*events[16]

    cdef struct VstMidiEvent:
        VstInt32 type
        VstInt32 byteSize
        VstInt32 deltaFrames
        VstInt32 flags
        VstInt32 noteLength
        VstInt32 noteOffset
        char midiData[4]
        char detune
        char noteOffVelocity
        char reserved1
        char reserved2

    cdef struct VstTimeInfo:
        double samplePos
        double sampleRate
        double nanoSeconds
        double ppqPos
        double tempo
        double barStartPos
        double cycleStartPos
        double cycleEndPos
        VstInt32 timeSigNumerator
        VstInt32 timeSigDenominator
        VstInt32 smpteOffset
        VstInt32 smpteFrameRate
        VstInt32 samplesToNextClock
        VstInt32 flags

    ctypedef VstIntPtr (*audioMasterCallback)(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt)
    ctypedef VstIntPtr (*AEffectDispatcherProc)(AEffect* effect, VstInt32 opcode, VstInt32 index, VstIntPtr value, void* ptr, float opt)
    ctypedef void (*AEffectProcessProc)(AEffect*effect, float** inputs, float** outputs, VstInt32 sample_frames)
    ctypedef void (*AEffectProcessDoubleProc)(AEffect* effect, double** inputs, double** outputs, VstInt32 sample_frames)
    ctypedef void (*AEffectSetParameterProc)(AEffect* effect, VstInt32 index, float parameter)
    ctypedef float (*AEffectGetParameterProc)(AEffect* effect, VstInt32 index)

    ctypedef struct AEffect:
        VstInt32 magic
        AEffectDispatcherProc dispatcher
        AEffectSetParameterProc setParameter
        AEffectGetParameterProc getParameter
        VstInt32 numPrograms
        VstInt32 numParams
        VstInt32 numInputs
        VstInt32 numOutputs
        VstInt32 flags
        VstIntPtr resvd1
        VstIntPtr resvd2
        VstInt32 initialDelay
        void* object
        void* user
        VstInt32 uniqueID
        VstInt32 version
        AEffectProcessProc processReplacing
        AEffectProcessDoubleProc processDoubleReplacing
        char future[56]

    cdef enum VstAEffectFlags:
        effFlagsHasEditor     = 1 << 0
        effFlagsCanReplacing  = 1 << 4
        effFlagsProgramChunks = 1 << 5
        effFlagsIsSynth       = 1 << 8
        effFlagsNoSoundInStop = 1 << 9
        effFlagsCanDoubleReplacing = 1 << 12

    cdef enum VstProcessLevels:
        kVstProcessLevelUnknown = 0
        kVstProcessLevelUser = 1
        kVstProcessLevelRealtime = 2
        kVstProcessLevelPrefetch = 3
        kVstProcessLevelOffline = 4

    cdef enum VstTimeInfoFlags:
        kVstTransportChanged = 1
        kVstTransportPlaying = 1 << 1
        kVstTransportCycleActive = 1 << 2
        kVstTransportRecording = 1 << 3
        kVstAutomationWriting = 1 << 6
        kVstAutomationReading = 1 << 7
        kVstNanosValid = 1 << 8
        kVstPpqPosValid = 1 << 9
        kVstTempoValid = 1 << 10
        kVstBarsValid = 1 << 11
        kVstCyclePosValid = 1 << 12
        kVstTimeSigValid = 1 << 13
        kVstSmpteValid = 1 << 14
        kVstClockValid = 1 << 15


# VST plugin dll entry_point "VSTPluginMain" typedef
ctypedef AEffect* (*VSTPluginMainPtr)(audioMasterCallback host)
