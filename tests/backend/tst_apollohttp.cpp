#include <QtTest>
#include <QTemporaryDir>
#include "backend/nvcomputer.h"
#include "backend/nvhttp.h"
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
};

QTEST_GUILESS_MAIN(ApolloHttpTest)
#include "tst_apollohttp.moc"
