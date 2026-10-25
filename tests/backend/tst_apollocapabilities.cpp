#include <QtTest>
#include "backend/apollocapabilities.h"

using Permission = ApolloCapabilities::Permission;

class ApolloCapabilitiesTest : public QObject
{
    Q_OBJECT

    static QString fixture(const char* name)
    {
        QFile file(QString(FIXTURE_DIR) + "/" + name);
        if (!file.open(QIODevice::ReadOnly)) qFatal("Missing fixture %s", name);
        return QString::fromUtf8(file.readAll());
    }

private slots:
    void permissionBitsMatchApollo()
    {
        // Apollo/Vibepollo src/crypto.h PERM layout
        QCOMPARE(uint32_t(Permission::InputController), uint32_t(0x00000100));
        QCOMPARE(uint32_t(Permission::InputKeyboard), uint32_t(0x00001000));
        QCOMPARE(uint32_t(Permission::ClipboardSet), uint32_t(0x00010000));
        QCOMPARE(uint32_t(Permission::ClipboardRead), uint32_t(0x00020000));
        QCOMPARE(uint32_t(Permission::FileUpload), uint32_t(0x00040000));
        QCOMPARE(uint32_t(Permission::FileDownload), uint32_t(0x00080000));
        QCOMPARE(uint32_t(Permission::ServerCommand), uint32_t(0x00100000));
        QCOMPARE(uint32_t(Permission::List), uint32_t(0x01000000));
        QCOMPARE(uint32_t(Permission::View), uint32_t(0x02000000));
        QCOMPARE(uint32_t(Permission::Launch), uint32_t(0x04000000));
    }

    void stockSunshineAdvertisesNothing()
    {
        const auto caps = ApolloCapabilities::fromServerInfo(fixture("serverinfo-sunshine.xml"));
        QVERIFY(!caps.permissionsKnown);
        QCOMPARE(caps.permissions, uint32_t(0));
        QVERIFY(caps.serverCommands.isEmpty());
        QVERIFY(!caps.virtualDisplayCapable);
        QVERIFY(!caps.virtualDisplayDriverReady);
        QVERIFY(!caps.virtualDisplayHdrCapable);
        // Unknown is never "allowed": features stay off on stock hosts
        QVERIFY(!caps.allows(Permission::ClipboardRead));
        QVERIFY(!caps.denies(Permission::ClipboardRead));
    }

    void apolloPairedHttps()
    {
        const auto caps = ApolloCapabilities::fromServerInfo(fixture("serverinfo-apollo.xml"));
        QVERIFY(caps.permissionsKnown);
        QCOMPARE(caps.permissions, uint32_t(119480064));
        QVERIFY(caps.allows(Permission::ClipboardSet));
        QVERIFY(caps.allows(Permission::ClipboardRead));
        QVERIFY(caps.allows(Permission::ServerCommand));
        QVERIFY(caps.allows(Permission::Launch));
        QCOMPARE(caps.serverCommands, QStringList({"Restart Explorer", "Lock Screen"}));
        QVERIFY(caps.virtualDisplayCapable);
        QVERIFY(caps.virtualDisplayDriverReady);
        // Apollo predates the HDR field
        QVERIFY(!caps.virtualDisplayHdrCapable);
    }

    void vibepolloPairedHttps()
    {
        const auto caps = ApolloCapabilities::fromServerInfo(fixture("serverinfo-vibepollo.xml"));
        QVERIFY(caps.permissionsKnown);
        QVERIFY(caps.allows(Permission::ClipboardRead));
        QVERIFY(caps.allows(Permission::ClipboardSet));
        QVERIFY(caps.denies(Permission::ServerCommand));
        QVERIFY(caps.denies(Permission::FileUpload));
        QVERIFY(caps.serverCommands.isEmpty());
        QVERIFY(caps.virtualDisplayCapable);
        QVERIFY(!caps.virtualDisplayDriverReady);
        QVERIFY(caps.virtualDisplayHdrCapable);
    }

    void zeroOverPlainHttpIsUnknown()
    {
        const auto caps = ApolloCapabilities::fromServerInfo(fixture("serverinfo-apollo-http.xml"));
        QVERIFY(!caps.permissionsKnown);
        QVERIFY(!caps.allows(Permission::ClipboardRead));
        QVERIFY(!caps.denies(Permission::ClipboardRead));
        QVERIFY(caps.virtualDisplayCapable);
    }

    void zeroWhilePairedIsDenied()
    {
        // A paired HTTPS answer reports the real mask, even when it is empty
        const auto caps = ApolloCapabilities::fromServerInfo(
            "<root><PairStatus>1</PairStatus><Permission>0</Permission></root>");
        QVERIFY(caps.permissionsKnown);
        QVERIFY(caps.denies(Permission::List));
    }

    void numericAndPaddedFlags()
    {
        const auto caps = ApolloCapabilities::fromServerInfo(
            "<root><VirtualDisplayCapable> 1 </VirtualDisplayCapable>"
            "<VirtualDisplayDriverReady>TRUE</VirtualDisplayDriverReady>"
            "<VirtualDisplayHDRCapable>0</VirtualDisplayHDRCapable>"
            "<ServerCommand>  </ServerCommand><ServerCommand>Sleep</ServerCommand></root>");
        QVERIFY(caps.virtualDisplayCapable);
        QVERIFY(caps.virtualDisplayDriverReady);
        QVERIFY(!caps.virtualDisplayHdrCapable);
        QCOMPARE(caps.serverCommands, QStringList({"Sleep"}));
    }

    void malformedClaimsNothing()
    {
        for (const QString& xml : {QString("<root><VirtualDisplayCapable>true</VirtualDisplayCapable>"),
                                  QString("<root><Permission>abc</Permission><PairStatus>1</PairStatus></root>"),
                                  QString("<root><VirtualDisplayCapable>yes</VirtualDisplayCapable></root>")}) {
            const auto caps = ApolloCapabilities::fromServerInfo(xml);
            QVERIFY(!caps.virtualDisplayCapable);
            QVERIFY(!caps.permissionsKnown);
        }
    }
};

QTEST_APPLESS_MAIN(ApolloCapabilitiesTest)
#include "tst_apollocapabilities.moc"
