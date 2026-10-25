#include <QtTest>
#include "backend/otppairing.h"

class OtpPairingTest : public QObject
{
    Q_OBJECT
private slots:
    void hashIsUppercaseSha256OfPinSaltPassphrase()
    {
        // Reference: Apollo src/nvhttp.cpp pair(), util::hex(crypto::hash(pin + salt + passphrase), true)
        QCOMPARE(OtpPairing::authHash("1234", "00112233445566778899aabbccddeeff", "secret"),
                 QString("7C58CCDAC53A01B66D8C5F2B36E0FE1D5910C2AD13C4C1260E74CA09E3B824C5"));
        // Non-ASCII passphrases are hashed as UTF-8, like the host's std::string
        QCOMPARE(OtpPairing::authHash("0420", "a1b2c3d4e5f60718293a4b5c6d7e8f90", QString::fromUtf8("pässwörd")),
                 QString("E406E9B24A810D1B07DD859BC7964BB1A8DEE8EDE029A3B4522FACE9882B63DC"));
    }

    void orderMatters()
    {
        QVERIFY(OtpPairing::authHash("1234", "ab", "cd") != OtpPairing::authHash("1234", "cd", "ab"));
    }

    void stockQueryUnchanged()
    {
        QCOMPARE(OtpPairing::getServerCertArguments("0a0b", "c0ffee", QString()),
                 QString("devicename=roth&updateState=1&phrase=getservercert&salt=0a0b&clientcert=c0ffee"));
    }

    void otpQueryAppendsAuth()
    {
        QCOMPARE(OtpPairing::getServerCertArguments("0a0b", "c0ffee", "ABCD"),
                 QString("devicename=roth&updateState=1&phrase=getservercert&salt=0a0b&clientcert=c0ffee&otpauth=ABCD"));
    }

    void pinAndPassphraseValidation()
    {
        // Apollo/Vibepollo request_otp(): four digits, passphrase of at least four characters
        QVERIFY(OtpPairing::isValidPin("0123"));
        QVERIFY(!OtpPairing::isValidPin("123"));
        QVERIFY(!OtpPairing::isValidPin("12345"));
        QVERIFY(!OtpPairing::isValidPin("12a4"));
        QVERIFY(!OtpPairing::isValidPin(QString::fromUtf8("١٢٣٤"))); // non-ASCII digits
        QVERIFY(OtpPairing::isValidPassphrase("abcd"));
        QVERIFY(!OtpPairing::isValidPassphrase("abc"));
    }
};

QTEST_APPLESS_MAIN(OtpPairingTest)
#include "tst_otppairing.moc"
