#pragma once

#include "nvapp.h"

#include <QString>

// Vibepollo adds synthetic apps to /applist that control the remote
// session instead of starting a game. Launching one is a normal launch;
// this only tells the UI what they are. Identities from Vibepollo
// src/remote_session.h and src/remote_session.cpp (control_identities).
namespace HostControls
{
enum class Kind
{
    None,
    Resume,
    DisconnectMonitor,
    DisconnectInput,
    Terminate,
    RemoteMonitor,
    RemoteInput,
    RunningGame,
};

struct Identity
{
    Kind kind;
    int primaryId;
    int secondaryId; // 0 if none
    int legacyId;    // 0 if none
    const char* uuid;
};

inline const Identity* identities(int& count)
{
    static const Identity table[] = {
        { Kind::Resume, 2147483501, 2147483511, 2147483601, "9a1c5a25-58fe-40e0-b9aa-7d3f00000001" },
        { Kind::DisconnectMonitor, 2147483502, 0, 2147483602, "9a1c5a25-58fe-40e0-b9aa-7d3f00000002" },
        { Kind::DisconnectInput, 2147483503, 0, 2147483603, "9a1c5a25-58fe-40e0-b9aa-7d3f00000003" },
        { Kind::Terminate, 2147483504, 2147483514, 2147483604, "9a1c5a25-58fe-40e0-b9aa-7d3f00000004" },
        { Kind::RemoteMonitor, 2147483505, 2147483515, 2147483605, "9a1c5a25-58fe-40e0-b9aa-7d3f00000005" },
        { Kind::RemoteInput, 2147483506, 2147483516, 2147483606, "9a1c5a25-58fe-40e0-b9aa-7d3f00000006" },
        { Kind::RunningGame, 2147483507, 0, 0, "9a1c5a25-58fe-40e0-b9aa-7d3f00000007" },
    };
    count = sizeof(table) / sizeof(table[0]);
    return table;
}

// Keyed on the app's UUID when /applist carries one. Hosts without UUIDs
// are matched on the fixed IDs, but only when idFallback is set: that is
// for hosts that identify as Apollo-family, so a stock host's app can
// never become a control by an ID collision.
inline Kind classify(const NvApp& app, bool idFallback)
{
    int count;
    const Identity* table = identities(count);

    if (!app.uuid.isEmpty()) {
        for (int i = 0; i < count; i++) {
            if (app.uuid.compare(QLatin1String(table[i].uuid), Qt::CaseInsensitive) == 0) {
                return table[i].kind;
            }
        }
        return Kind::None;
    }

    if (idFallback && app.id > 0) {
        for (int i = 0; i < count; i++) {
            if (app.id == table[i].primaryId || app.id == table[i].secondaryId || app.id == table[i].legacyId) {
                return table[i].kind;
            }
        }
    }

    return Kind::None;
}

// Stable names for QML
inline QString name(Kind kind)
{
    switch (kind) {
    case Kind::Resume: return QStringLiteral("resume");
    case Kind::DisconnectMonitor: return QStringLiteral("disconnectMonitor");
    case Kind::DisconnectInput: return QStringLiteral("disconnectInput");
    case Kind::Terminate: return QStringLiteral("terminate");
    case Kind::RemoteMonitor: return QStringLiteral("remoteMonitor");
    case Kind::RemoteInput: return QStringLiteral("remoteInput");
    case Kind::RunningGame: return QStringLiteral("runningGame");
    case Kind::None: break;
    }
    return QString();
}
}
