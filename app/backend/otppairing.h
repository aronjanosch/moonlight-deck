#pragma once

#include <QCryptographicHash>
#include <QString>

// One-time PIN pairing for Apollo and Vibepollo hosts. The user creates a
// PIN and passphrase in the host's web UI; the client proves knowledge of
// both in the first pairing request and the normal PIN exchange continues
// with that PIN. Ported from Artemis Qt app/backend/otppairingmanager.cpp,
// checked against Apollo src/nvhttp.cpp pair() and request_otp().
namespace OtpPairing
{
// Uppercase hex SHA-256 of pin + salt + passphrase, where salt is the hex
// string sent as the "salt" query argument.
inline QString authHash(const QString& pin, const QString& salt, const QString& passphrase)
{
    const QByteArray plainText = (pin + salt + passphrase).toUtf8();
    return QString::fromLatin1(QCryptographicHash::hash(plainText, QCryptographicHash::Sha256).toHex().toUpper());
}

// Arguments of the first pairing phase. Without otpAuth this is the stock
// Moonlight request.
inline QString getServerCertArguments(const QString& salt, const QString& clientCert, const QString& otpAuth)
{
    QString arguments = "devicename=roth&updateState=1&phrase=getservercert&salt=" + salt +
                        "&clientcert=" + clientCert;
    if (!otpAuth.isEmpty()) {
        arguments += "&otpauth=" + otpAuth;
    }
    return arguments;
}

inline bool isValidPin(const QString& pin)
{
    if (pin.length() != 4) {
        return false;
    }
    for (const QChar c : pin) {
        if (c < QLatin1Char('0') || c > QLatin1Char('9')) {
            return false;
        }
    }
    return true;
}

inline bool isValidPassphrase(const QString& passphrase)
{
    // The host refuses to create a one-time PIN with a shorter passphrase
    return passphrase.toUtf8().size() >= 4;
}
}
