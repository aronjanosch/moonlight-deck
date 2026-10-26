#include <QtTest>
#include <QTemporaryDir>
#include "backend/nvcomputer.h"
#include "backend/nvhttp.h"
#include "backend/apollocapabilities.h"
#include "../power/tlsfixture.h"

extern "C" const char* LiGetLaunchUrlQueryParameters(void) { return "&corever=1"; }

// Requests the client sends to Apollo/Vibepollo hosts. Every host here is
// a loopback TLS mock; no real host is contacted.
class ApolloHttpTest : public QObject {
    Q_OBJECT
    QTemporaryDir settings;
    TlsCredentials paired;

    NvHTTP* http(TlsServer& server) {
        return new NvHTTP(NvAddress("127.0.0.1", 47989), server.serverPort(), paired.certificate, true);
    }

    static QByteArray launchOk() {
        return "<root status_code=\"200\"><sessionUrl0>rtsp://127.0.0.1:48010</sessionUrl0><gamesession>1</gamesession></root>";
    }

    static void launch(NvHTTP& client, const char* verb) {
        STREAM_CONFIGURATION config = {};
        config.width = 1280;
        config.height = 800;
        config.fps = 60;
        QString rtspSessionUrl;
        LaunchWarning::Code warning;
        client.startApp(verb, false, 1001, &config, true, false, 1, 0, false, false, rtspSessionUrl, warning);
        QCOMPARE(rtspSessionUrl, QString("rtsp://127.0.0.1:48010"));
    }

private slots:
    void initTestCase() {
        QVERIFY(settings.isValid());
        QCoreApplication::setOrganizationName("MoonlightApolloHttpTest");
        QCoreApplication::setApplicationName("Isolated");
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settings.path());
        paired = TlsCredentials::generate(settings.path(), "paired");
        QVERIFY(!paired.certificate.isNull());
    }

    void launchFromComputerFollowsHostCapability() {
        // Session code builds NvHTTP from the NvComputer, which carries both
        // the user's choice and what the host advertised
        struct Case { bool requested; bool capable; bool expected; };
        for (const Case c : {Case{false, false, false}, Case{false, true, false},
                             Case{true, false, false}, Case{true, true, true}}) {
            TlsServer server(paired); server.results = {{launchOk()}};
            NvComputer computer;
            computer.activeAddress = NvAddress("127.0.0.1", 47989);
            computer.activeHttpsPort = server.serverPort();
            computer.serverCert = paired.certificate;
            computer.isNvidiaServerSoftware = false;
            computer.requestVirtualDisplay = c.requested;
            computer.virtualDisplayCapable = c.capable;
            NvHTTP client(&computer);
            launch(client, "launch");
            QCOMPARE(server.requests.size(), 1);
            QCOMPARE(server.requests[0].line.contains("virtualDisplay=1"), c.expected);
            QVERIFY(!server.requests[0].line.contains("virtualDisplay=0"));
        }
    }

    void launchWithoutVirtualDisplayIsUnchanged() {
        for (const char* verb : {"launch", "resume"}) {
            TlsServer server(paired); server.results = {{launchOk()}};
            QScopedPointer<NvHTTP> client(http(server));
            launch(*client, verb);
            QCOMPARE(server.requests.size(), 1);
            QVERIFY(server.requests[0].line.startsWith(QByteArray("GET /") + verb + "?"));
            // Never an explicit virtualDisplay=0: Vibepollo treats that as a request to disable it
            QVERIFY(!server.requests[0].line.contains("virtualDisplay"));
        }
    }

    void launchAndResumeRequestVirtualDisplay() {
        for (const char* verb : {"launch", "resume"}) {
            TlsServer server(paired); server.results = {{launchOk()}};
            QScopedPointer<NvHTTP> client(http(server));
            client->setRequestVirtualDisplay(true);
            launch(*client, verb);
            QCOMPARE(server.requests.size(), 1);
            const auto line = server.requests[0].line;
            QVERIFY(line.contains("&virtualDisplay=1&corever=1 "));
            QCOMPARE(line.count("virtualDisplay"), 1);
        }
    }

    void appListCarriesUuids() {
        TlsServer server(paired);
        server.results = {{"<root status_code=\"200\">"
                           "<App><IsHdrSupported>0</IsHdrSupported><AppTitle>Desktop</AppTitle><UUID>0B5E3E2C-1111-4A4A-9C9C-000000000001</UUID><ID>1001</ID></App>"
                           "<App><IsHdrSupported>0</IsHdrSupported><AppTitle>  Resume</AppTitle><UUID>9a1c5a25-58fe-40e0-b9aa-7d3f00000001</UUID><IDX>2147483511</IDX><ID>2147483511</ID></App>"
                           "<App><IsHdrSupported>1</IsHdrSupported><AppTitle>Stock</AppTitle><ID>1002</ID></App>"
                           "</root>"}};
        QScopedPointer<NvHTTP> client(http(server));
        const auto apps = client->getAppList();
        QCOMPARE(apps.size(), 3);
        QCOMPARE(apps[0].uuid, QString("0B5E3E2C-1111-4A4A-9C9C-000000000001"));
        QCOMPARE(apps[1].uuid, QString("9a1c5a25-58fe-40e0-b9aa-7d3f00000001"));
        QCOMPARE(apps[1].id, 2147483511);
        QCOMPARE(apps[1].name, QString("  Resume"));
        // Stock hosts send no UUID
        QVERIFY(apps[2].uuid.isEmpty());
        QVERIFY(apps[2].hdrSupported);
    }

    // Clipboard over the paired HTTPS port (Apollo/Vibepollo). Vibepollo only
    // answers during a stream; the client must never call a host that didn't
    // grant the permission, and stock hosts grant nothing.
    void clipboardRead() {
        TlsServer server(paired); server.results = {{QString::fromUtf8("Grüße ✓").toUtf8()}};
        QScopedPointer<NvHTTP> client(http(server));
        client->setApolloPermissions(true, uint32_t(ApolloCapabilities::Permission::ClipboardRead));
        QVERIFY(client->canReadClipboard());
        QVERIFY(!client->canSetClipboard());
        QCOMPARE(client->getClipboardText(), QString::fromUtf8("Grüße ✓"));
        QCOMPARE(server.requests.size(), 1);
        QVERIFY(server.requests[0].line.startsWith("GET /actions/clipboard?uniqueid="));
        QVERIFY(server.requests[0].line.endsWith("&type=text HTTP/1.1"));
    }

    void clipboardSet() {
        TlsServer server(paired); server.results = {{QByteArray()}};
        QScopedPointer<NvHTTP> client(http(server));
        client->setApolloPermissions(true, uint32_t(ApolloCapabilities::Permission::ClipboardSet));
        client->setClipboardText(QString::fromUtf8("line 1\nGrüße"));
        QCOMPARE(server.requests.size(), 1);
        const auto request = server.requests[0];
        QVERIFY(request.line.startsWith("POST /actions/clipboard?uniqueid="));
        QVERIFY(request.line.endsWith("&type=text HTTP/1.1"));
        QVERIFY(request.headers.toLower().contains("content-type: text/plain; charset=utf-8"));
        QCOMPARE(request.body, QString::fromUtf8("line 1\nGrüße").toUtf8());
    }

    void clipboardNeverSentWithoutPermission() {
        struct Case { bool known; uint32_t mask; bool hasPair; };
        const uint32_t otherBits = uint32_t(ApolloCapabilities::Permission::List) |
                                   uint32_t(ApolloCapabilities::Permission::Launch);
        const uint32_t clipboard = uint32_t(ApolloCapabilities::Permission::ClipboardRead) |
                                   uint32_t(ApolloCapabilities::Permission::ClipboardSet);
        for (const Case c : {Case{false, 0, true},           // stock host: no mask at all
                             Case{false, clipboard, true},   // never trust an unknown mask
                             Case{true, otherBits, true},    // denied by the host
                             Case{true, clipboard, false}}) { // not paired
            TlsServer server(paired); server.results = {{"must not be requested"}};
            QScopedPointer<NvHTTP> client(c.hasPair ? http(server)
                : new NvHTTP(NvAddress("127.0.0.1", 47989), server.serverPort(), QSslCertificate(), true));
            client->setApolloPermissions(c.known, c.mask);
            bool readThrew = false, setThrew = false;
            try { client->getClipboardText(); } catch (const std::exception&) { readThrew = true; }
            try { client->setClipboardText("secret"); } catch (const std::exception&) { setThrew = true; }
            QVERIFY(readThrew && setThrew);
            QVERIFY(!client->canReadClipboard() && !client->canSetClipboard());
            QCoreApplication::processEvents();
            QCOMPARE(server.connections, 0);
            QVERIFY(server.requests.isEmpty());
        }
    }

    void clipboardHostRefusalThrows() {
        // Apollo/Vibepollo answer 403 to a client that is not streaming
        TlsServer server(paired); server.results = {{QByteArray(), 403}};
        QScopedPointer<NvHTTP> client(http(server));
        client->setApolloPermissions(true, uint32_t(ApolloCapabilities::Permission::ClipboardRead));
        bool threw = false;
        try { client->getClipboardText(); } catch (const std::exception&) { threw = true; }
        QVERIFY(threw);
        QCOMPARE(server.requests.size(), 1);
    }

    void clipboardPermissionsComeFromTheComputer() {
        TlsServer server(paired); server.results = {{"from host"}};
        NvComputer computer;
        computer.activeAddress = NvAddress("127.0.0.1", 47989);
        computer.activeHttpsPort = server.serverPort();
        computer.serverCert = paired.certificate;
        computer.isNvidiaServerSoftware = false;
        computer.apolloPermissionsKnown = true;
        computer.apolloPermissions = uint32_t(ApolloCapabilities::Permission::ClipboardRead);
        NvHTTP client(&computer);
        QVERIFY(client.canReadClipboard());
        QVERIFY(!client.canSetClipboard());
        QCOMPARE(client.getClipboardText(), QString("from host"));

        // A stock host never advertises a mask
        NvComputer stock = computer;
        stock.apolloPermissionsKnown = false;
        stock.apolloPermissions = 0;
        NvHTTP stockClient(&stock);
        QVERIFY(!stockClient.canReadClipboard() && !stockClient.canSetClipboard());
    }
};

QTEST_GUILESS_MAIN(ApolloHttpTest)
#include "tst_apollohttp.moc"
