TEMPLATE = app
TARGET = tst_otppairing
QT = core testlib
CONFIG += console testcase c++17
CONFIG -= app_bundle
INCLUDEPATH += $$PWD/../../app
SOURCES += $$PWD/tst_otppairing.cpp
HEADERS += $$PWD/../../app/backend/otppairing.h
