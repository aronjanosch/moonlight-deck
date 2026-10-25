#pragma once

#include <QString>
#include <QStringList>
#include <QXmlStreamReader>
#include <cstdint>

// Optional /serverinfo extensions from Apollo and Vibepollo. Stock Sunshine
// and GFE send none of these, so every field defaults to "not offered".
struct ApolloCapabilities
{
    // Bit layout of PERM in Apollo/Vibepollo src/crypto.h
    enum class Permission : uint32_t
    {
        InputController = 1u << 8,
        InputTouch = 1u << 9,
        InputPen = 1u << 10,
        InputMouse = 1u << 11,
        InputKeyboard = 1u << 12,

        ClipboardSet = 1u << 16,
        ClipboardRead = 1u << 17,
        FileUpload = 1u << 18,
        FileDownload = 1u << 19,
        ServerCommand = 1u << 20,

        List = 1u << 24,
        View = 1u << 25,
        Launch = 1u << 26,
    };

    // Hosts answer plain HTTP with a placeholder 0, and stock hosts send no
    // mask at all. Only a mask from a paired (HTTPS) answer is meaningful.
    bool permissionsKnown = false;
    uint32_t permissions = 0;
    QStringList serverCommands;
    bool virtualDisplayCapable = false;
    bool virtualDisplayDriverReady = false;
    bool virtualDisplayHdrCapable = false;

    bool allows(Permission permission) const
    {
        return permissionsKnown && (permissions & uint32_t(permission)) != 0;
    }

    bool denies(Permission permission) const
    {
        return permissionsKnown && (permissions & uint32_t(permission)) == 0;
    }

    static ApolloCapabilities fromServerInfo(const QString& serverInfo)
    {
        ApolloCapabilities result;
        bool hasPermission = false, validPermission = false, paired = false;
        QXmlStreamReader xml(serverInfo);
        while (!xml.atEnd()) {
            if (xml.readNext() != QXmlStreamReader::StartElement) continue;
            const auto name = xml.name().toString();
            if (name != "Permission" && name != "ServerCommand" && name != "PairStatus" &&
                name != "VirtualDisplayCapable" && name != "VirtualDisplayDriverReady" &&
                name != "VirtualDisplayHDRCapable") continue;
            const auto value = xml.readElementText().trimmed();
            const bool flag = value == "1" || value.compare("true", Qt::CaseInsensitive) == 0;
            if (name == "Permission") {
                hasPermission = true;
                result.permissions = value.toUInt(&validPermission);
            }
            else if (name == "ServerCommand") {
                if (!value.isEmpty()) result.serverCommands.append(value);
            }
            else if (name == "PairStatus") paired = value == "1";
            else if (name == "VirtualDisplayCapable") result.virtualDisplayCapable = flag;
            else if (name == "VirtualDisplayDriverReady") result.virtualDisplayDriverReady = flag;
            else result.virtualDisplayHdrCapable = flag;
        }
        if (xml.hasError()) return ApolloCapabilities{};
        if (!validPermission) result.permissions = 0;
        result.permissionsKnown = hasPermission && validPermission && (result.permissions != 0 || paired);
        return result;
    }
};
