TEMPLATE = app
TARGET = tst_hostcontrols
QT = core testlib
CONFIG += console testcase c++17
CONFIG -= app_bundle
INCLUDEPATH += $$PWD/../../app
SOURCES += $$PWD/tst_hostcontrols.cpp $$PWD/../../app/backend/nvapp.cpp
HEADERS += $$PWD/../../app/backend/hostcontrols.h $$PWD/../../app/backend/nvapp.h
