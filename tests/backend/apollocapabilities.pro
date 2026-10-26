TEMPLATE = app
TARGET = tst_apollocapabilities
QT = core testlib
CONFIG += console testcase c++17
CONFIG -= app_bundle
DEFINES += FIXTURE_DIR=\\\"$$PWD/fixtures\\\"
INCLUDEPATH += $$PWD/../../app
SOURCES += $$PWD/tst_apollocapabilities.cpp
HEADERS += $$PWD/../../app/backend/apollocapabilities.h
