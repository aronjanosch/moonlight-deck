#include <QtTest>
#include "backend/hostcontrols.h"

using Kind = HostControls::Kind;

class HostControlsTest : public QObject
{
    Q_OBJECT

    static NvApp app(int id, const QString& uuid = QString(), const QString& name = "App")
    {
        NvApp result;
        result.id = id;
        result.uuid = uuid;
        result.name = name;
        return result;
    }

private slots:
    void fixedUuids()
    {
        // Vibepollo src/remote_session.cpp control_identities
        const QString base = "9a1c5a25-58fe-40e0-b9aa-7d3f0000000%1";
        QCOMPARE(HostControls::classify(app(2147483501, base.arg(1)), false), Kind::Resume);
        QCOMPARE(HostControls::classify(app(2147483502, base.arg(2)), false), Kind::DisconnectMonitor);
        QCOMPARE(HostControls::classify(app(2147483503, base.arg(3)), false), Kind::DisconnectInput);
        QCOMPARE(HostControls::classify(app(2147483504, base.arg(4)), false), Kind::Terminate);
        QCOMPARE(HostControls::classify(app(2147483505, base.arg(5)), false), Kind::RemoteMonitor);
        QCOMPARE(HostControls::classify(app(2147483506, base.arg(6)), false), Kind::RemoteInput);
        QCOMPARE(HostControls::classify(app(2147483507, base.arg(7)), false), Kind::RunningGame);
        // Secondary IDs share the primary UUID
        QCOMPARE(HostControls::classify(app(2147483511, base.arg(1)), false), Kind::Resume);
        // Case doesn't matter
        QCOMPARE(HostControls::classify(app(5, base.arg(4).toUpper()), false), Kind::Terminate);
    }

    void uuidWinsOverId()
    {
        // A configured app with its own UUID is a game, whatever its ID
        QCOMPARE(HostControls::classify(app(2147483504, "0b5e3e2c-1111-4a4a-9c9c-000000000001"), true), Kind::None);
        QCOMPARE(HostControls::classify(app(1001, "0b5e3e2c-1111-4a4a-9c9c-000000000001"), true), Kind::None);
        QCOMPARE(HostControls::classify(app(1001, "9a1c5a25-58fe-40e0-b9aa-7d3f00000008"), true), Kind::None);
    }

    void idFallbackWithoutUuid()
    {
        // Primary, secondary and legacy IDs from Vibepollo src/remote_session.{h,cpp}
        const QList<QPair<int, Kind>> ids = {
            {2147483501, Kind::Resume}, {2147483502, Kind::DisconnectMonitor},
            {2147483503, Kind::DisconnectInput}, {2147483504, Kind::Terminate},
            {2147483505, Kind::RemoteMonitor}, {2147483506, Kind::RemoteInput},
            {2147483507, Kind::RunningGame},
            {2147483511, Kind::Resume}, {2147483514, Kind::Terminate},
            {2147483515, Kind::RemoteMonitor}, {2147483516, Kind::RemoteInput},
            {2147483601, Kind::Resume}, {2147483606, Kind::RemoteInput},
        };
        for (const auto& id : ids) {
            QCOMPARE(HostControls::classify(app(id.first), true), id.second);
        }
        QCOMPARE(HostControls::classify(app(2147483512), true), Kind::None);
        QCOMPARE(HostControls::classify(app(2147483513), true), Kind::None);
        QCOMPARE(HostControls::classify(app(2147483508), true), Kind::None);
        QCOMPARE(HostControls::classify(app(1001), true), Kind::None);
    }

    void stockHostsNeverGetControls()
    {
        // Without an Apollo-family host, a colliding numeric ID stays a game
        QCOMPARE(HostControls::classify(app(2147483504), false), Kind::None);
        QCOMPARE(HostControls::classify(app(2147483501), false), Kind::None);
    }

    void names()
    {
        QCOMPARE(HostControls::name(Kind::Resume), QString("resume"));
        QCOMPARE(HostControls::name(Kind::RunningGame), QString("runningGame"));
        QCOMPARE(HostControls::name(Kind::None), QString());
    }

    void appUuidIsSerializedAndCompared()
    {
        QTemporaryDir dir;
        QSettings settings(dir.filePath("apps.ini"), QSettings::IniFormat);
        const auto original = app(2147483501, "9a1c5a25-58fe-40e0-b9aa-7d3f00000001", "Resume");
        original.serialize(settings);
        const NvApp restored(settings);
        QCOMPARE(restored.uuid, original.uuid);
        QVERIFY(restored == original);
        QVERIFY(app(1, "a") != app(1, "b"));
    }
};

QTEST_APPLESS_MAIN(HostControlsTest)
#include "tst_hostcontrols.moc"
