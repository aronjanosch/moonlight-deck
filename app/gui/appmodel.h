#pragma once

#include "backend/boxartmanager.h"
#include "backend/computermanager.h"
#include "backend/hostcontrols.h"
#include "streaming/session.h"

#include <QAbstractListModel>

class AppModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool frameLimiterSupported READ frameLimiterSupported NOTIFY frameLimiterChanged)
    Q_PROPERTY(bool frameLimiterEnabled READ frameLimiterEnabled NOTIFY frameLimiterChanged)
    Q_PROPERTY(bool virtualDisplayFrameLimiterEnabled READ virtualDisplayFrameLimiterEnabled NOTIFY frameLimiterChanged)
    Q_PROPERTY(double frameLimiterFpsLimit READ frameLimiterFpsLimit NOTIFY frameLimiterChanged)

    enum Roles
    {
        NameRole = Qt::UserRole,
        RunningRole,
        BoxArtRole,
        HiddenRole,
        AppIdRole,
        DirectLaunchRole,
        AppCollectorGameRole,
        SleepActionRole,
        HostControlRole,
    };

public:
    explicit AppModel(QObject *parent = nullptr);
    bool frameLimiterSupported() const;
    bool frameLimiterEnabled() const;
    bool virtualDisplayFrameLimiterEnabled() const;
    double frameLimiterFpsLimit() const;

    // Must be called before any QAbstractListModel functions. With
    // groupHostControls, Vibepollo's session controls follow the games.
    Q_INVOKABLE void initialize(ComputerManager* computerManager, int computerIndex, bool showHiddenGames,
                                bool groupHostControls = false);

    Q_INVOKABLE Session* createSessionForApp(int appIndex);

    Q_INVOKABLE int getDirectLaunchAppIndex();

    Q_INVOKABLE int getRunningAppId();

    Q_INVOKABLE QString getRunningAppName();

    Q_INVOKABLE void quitRunningApp();

    Q_INVOKABLE void requestHostSleep();

    Q_INVOKABLE void setAppHidden(int appIndex, bool hidden);

    Q_INVOKABLE void setAppDirectLaunch(int appIndex, bool directLaunch);

    QVariant data(const QModelIndex &index, int role) const override;

    int rowCount(const QModelIndex &parent) const override;

    virtual QHash<int, QByteArray> roleNames() const override;

private slots:
    void handleComputerStateChanged(NvComputer* computer);

    void handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl image);

signals:
    void computerLost();
    void frameLimiterChanged();
    void hostSleepCompleted(QString error);

private:
    void updateAppList(QVector<NvApp> newList);

    QVector<NvApp> getVisibleApps(const QVector<NvApp>& appList);

    bool isAppCurrentlyVisible(const NvApp& app);

    HostControls::Kind hostControl(const NvApp& app) const;

    bool appLessThan(const NvApp& app1, const NvApp& app2) const;

    void updateSleepAction();
    bool m_SleepActionVisible = false;
    void updateFrameLimiterCapabilities();
    bool m_FrameLimiterSupported = false;
    bool m_FrameLimiterEnabled = false;
    bool m_VirtualDisplayFrameLimiterEnabled = false;
    double m_FrameLimiterFpsLimit = 0;
    NvComputer* m_Computer = nullptr;
    BoxArtManager m_BoxArtManager;
    ComputerManager* m_ComputerManager;
    QVector<NvApp> m_VisibleApps, m_AllApps;
    int m_CurrentGameId;
    bool m_ShowHiddenGames;
    bool m_GroupHostControls = false;
    // Snapshot of whether the host identifies as Apollo-family, so its
    // apps without a UUID may be matched to controls by ID
    bool m_ControlIdFallback = false;
};
