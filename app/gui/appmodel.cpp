#include "appmodel.h"

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_BoxArtManager, &BoxArtManager::boxArtLoadComplete,
            this, &AppModel::handleBoxArtLoaded);
}

bool AppModel::frameLimiterSupported() const { return m_FrameLimiterSupported; }
bool AppModel::frameLimiterEnabled() const { return m_FrameLimiterEnabled; }
bool AppModel::virtualDisplayFrameLimiterEnabled() const { return m_VirtualDisplayFrameLimiterEnabled; }
double AppModel::frameLimiterFpsLimit() const { return m_FrameLimiterFpsLimit; }

void AppModel::updateFrameLimiterCapabilities()
{
    // Snapshot discovery state; QML getters use only this GUI-thread cache.
    QReadLocker locker(&m_Computer->lock);
    const bool changed = m_FrameLimiterSupported != m_Computer->frameLimiterSupported ||
        m_FrameLimiterEnabled != m_Computer->frameLimiterEnabled ||
        m_VirtualDisplayFrameLimiterEnabled != m_Computer->virtualDisplayFrameLimiterEnabled ||
        m_FrameLimiterFpsLimit != m_Computer->frameLimiterFpsLimitMilliHz / 1000.0;
    m_FrameLimiterSupported = m_Computer->frameLimiterSupported;
    m_FrameLimiterEnabled = m_Computer->frameLimiterEnabled;
    m_VirtualDisplayFrameLimiterEnabled = m_Computer->virtualDisplayFrameLimiterEnabled;
    m_FrameLimiterFpsLimit = m_Computer->frameLimiterFpsLimitMilliHz / 1000.0;
    locker.unlock();
    if (changed) emit frameLimiterChanged();
}

void AppModel::initialize(ComputerManager* computerManager, int computerIndex, bool showHiddenGames,
                          bool groupHostControls)
{
    m_ComputerManager = computerManager;
    connect(m_ComputerManager, &ComputerManager::computerStateChanged,
            this, &AppModel::handleComputerStateChanged);

    Q_ASSERT(computerIndex < m_ComputerManager->getComputers().count());
    m_Computer = m_ComputerManager->getComputers().at(computerIndex);
    m_CurrentGameId = m_Computer->currentGameId;
    m_ShowHiddenGames = showHiddenGames;
    m_GroupHostControls = groupHostControls;
    {
        QReadLocker lock(&m_Computer->lock);
        m_ControlIdFallback = m_Computer->otpPairingSupported;
    }

    updateAppList(m_Computer->appList);
    updateFrameLimiterCapabilities();
    updateSleepAction();
    const QString uuid = m_Computer->uuid;
    connect(m_ComputerManager, &ComputerManager::hostSleepCompleted, this,
            [this, uuid](const QString& completedUuid, const QString& error) {
        if (completedUuid == uuid) emit hostSleepCompleted(error);
    });
}

int AppModel::getRunningAppId()
{
    return m_CurrentGameId;
}

QString AppModel::getRunningAppName()
{
    if (m_CurrentGameId != 0) {
        for (int i = 0; i < m_AllApps.count(); i++) {
            if (m_AllApps[i].id == m_CurrentGameId) {
                return m_AllApps[i].name;
            }
        }
    }

    return nullptr;
}

Session* AppModel::createSessionForApp(int appIndex)
{
    // The synthetic power row must never construct a streaming Session.
    if (appIndex < 0 || appIndex >= m_VisibleApps.count()) return nullptr;
    NvApp app = m_VisibleApps.at(appIndex);

    return new Session(m_Computer, app);
}

int AppModel::getDirectLaunchAppIndex()
{
    for (int i = 0; i < m_VisibleApps.count(); i++) {
        if (m_VisibleApps[i].directLaunch) {
            return i;
        }
    }

    return -1;
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    // For list models only the root node (an invalid parent) should return the list's size. For all
    // other (valid) parents, rowCount() should return 0 so that it does not become a tree model.
    if (parent.isValid())
        return 0;

    return m_VisibleApps.count() + (m_SleepActionVisible ? 1 : 0);
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid())
        return QVariant();

    if (index.row() == m_VisibleApps.count() && m_SleepActionVisible) {
        switch (role) {
        case NameRole: return tr("Put PC to Sleep");
        case BoxArtRole: return QUrl("qrc:/res/no_app_image.png");
        case SleepActionRole: return true;
        case AppIdRole: return 0; // No real app ID; never sent to a host.
        case RunningRole: case HiddenRole: case DirectLaunchRole: case AppCollectorGameRole: return false;
        case HostControlRole: return QString();
        default: return QVariant();
        }
    }
    if (index.row() < 0 || index.row() >= m_VisibleApps.count()) return QVariant();
    NvApp app = m_VisibleApps.at(index.row());
    const bool groupedControl = m_GroupHostControls && hostControl(app) != HostControls::Kind::None;

    switch (role)
    {
    case NameRole:
        // Vibepollo pads some control titles with spaces to rank them
        return groupedControl ? app.name.trimmed() : app.name;
    case RunningRole:
        return m_Computer->currentGameId == app.id;
    case BoxArtRole:
        // Grouped controls are drawn as tiles with their own icon
        if (groupedControl) {
            return QUrl();
        }
        // FIXME: const-correctness
        return const_cast<BoxArtManager&>(m_BoxArtManager).loadBoxArt(m_Computer, app);
    case HiddenRole:
        return app.hidden;
    case AppIdRole:
        return app.id;
    case DirectLaunchRole:
        return app.directLaunch;
    case AppCollectorGameRole:
        return app.isAppCollectorGame;
    case SleepActionRole:
        return false;
    case HostControlRole:
        return HostControls::name(hostControl(app));
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    QHash<int, QByteArray> names;

    names[NameRole] = "name";
    names[RunningRole] = "running";
    names[BoxArtRole] = "boxart";
    names[HiddenRole] = "hidden";
    names[AppIdRole] = "appid";
    names[DirectLaunchRole] = "directLaunch";
    names[AppCollectorGameRole] = "appCollectorGame";
    names[SleepActionRole] = "sleepAction";
    names[HostControlRole] = "hostControl";

    return names;
}

void AppModel::quitRunningApp()
{
    m_ComputerManager->quitRunningApp(m_Computer);
}

void AppModel::updateSleepAction()
{
    QReadLocker lock(&m_Computer->lock);
    const bool visible = m_Computer->sleepActionSupportedAndAllowed;
    lock.unlock(); // Model notifications can re-enter UI/backend code.
    if (visible == m_SleepActionVisible) return;
    const int row = m_VisibleApps.count();
    if (visible) beginInsertRows(QModelIndex(), row, row);
    else beginRemoveRows(QModelIndex(), row, row);
    m_SleepActionVisible = visible;
    if (visible) endInsertRows();
    else endRemoveRows();
}

void AppModel::requestHostSleep()
{
    if (!m_SleepActionVisible || !m_ComputerManager->requestHostSleep(m_Computer))
        emit hostSleepCompleted(tr("Sleep is unavailable or a request is already pending."));
}

HostControls::Kind AppModel::hostControl(const NvApp& app) const
{
    // Numeric IDs are only trusted from hosts that identify as Apollo-family
    return HostControls::classify(app, m_ControlIdFallback);
}

bool AppModel::appLessThan(const NvApp& app1, const NvApp& app2) const
{
    if (m_GroupHostControls) {
        const bool control1 = hostControl(app1) != HostControls::Kind::None;
        const bool control2 = hostControl(app2) != HostControls::Kind::None;
        if (control1 != control2) {
            return control2;
        }
        // Controls keep the order Vibepollo ranks them in with leading spaces
    }

    return app1.name.toLower() < app2.name.toLower();
}

bool AppModel::isAppCurrentlyVisible(const NvApp& app)
{
    for (const NvApp& visibleApp : std::as_const(m_VisibleApps)) {
        if (app.id == visibleApp.id) {
            return true;
        }
    }

    return false;
}

QVector<NvApp> AppModel::getVisibleApps(const QVector<NvApp>& appList)
{
    QVector<NvApp> visibleApps;

    for (const NvApp& app : appList) {
        // Don't immediately hide games that were previously visible. This
        // allows users to easily uncheck the "Hide App" checkbox if they
        // check it by mistake.
        if (m_ShowHiddenGames || !app.hidden || isAppCurrentlyVisible(app)) {
            visibleApps.append(app);
        }
    }

    // The host's list is already sorted by name
    if (m_GroupHostControls) {
        std::stable_sort(visibleApps.begin(), visibleApps.end(), [this](const NvApp& app1, const NvApp& app2) {
            return appLessThan(app1, app2);
        });
    }

    return visibleApps;
}

void AppModel::updateAppList(QVector<NvApp> newList)
{
    m_AllApps = newList;

    QVector<NvApp> newVisibleList = getVisibleApps(newList);

    // Process removals and updates first
    for (int i = 0; i < m_VisibleApps.count(); i++) {
        const NvApp& existingApp = m_VisibleApps.at(i);

        bool found = false;
        for (const NvApp& newApp : std::as_const(newVisibleList)) {
            if (existingApp.id == newApp.id) {
                // If the data changed, update it in our list
                if (existingApp != newApp) {
                    m_VisibleApps.replace(i, newApp);
                    emit dataChanged(createIndex(i, 0), createIndex(i, 0));
                }

                found = true;
                break;
            }
        }

        if (!found) {
            beginRemoveRows(QModelIndex(), i, i);
            m_VisibleApps.removeAt(i);
            endRemoveRows();
            i--;
        }
    }

    // Process additions now
    for (const NvApp& newApp : std::as_const(newVisibleList)) {
        int insertionIndex = m_VisibleApps.size();
        bool found = false;

        for (int i = 0; i < m_VisibleApps.count(); i++) {
            const NvApp& existingApp = m_VisibleApps.at(i);

            if (existingApp.id == newApp.id) {
                found = true;
                break;
            }
            else if (appLessThan(newApp, existingApp)) {
                insertionIndex = i;
                break;
            }
        }

        if (!found) {
            beginInsertRows(QModelIndex(), insertionIndex, insertionIndex);
            m_VisibleApps.insert(insertionIndex, newApp);
            endInsertRows();
        }
    }

    Q_ASSERT(newVisibleList == m_VisibleApps);
}

void AppModel::setAppHidden(int appIndex, bool hidden)
{
    if (appIndex < 0 || appIndex >= m_VisibleApps.count()) return;
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (app.id == appId) {
                app.hidden = hidden;
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::setAppDirectLaunch(int appIndex, bool directLaunch)
{
    if (appIndex < 0 || appIndex >= m_VisibleApps.count()) return;
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (directLaunch) {
                // We must clear direct launch from all other apps
                // to set it on the new app.
                app.directLaunch = app.id == appId;
            }
            else if (app.id == appId) {
                // If we're clearing direct launch, we're done once we
                // find our matching app ID.
                app.directLaunch = false;
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::handleComputerStateChanged(NvComputer* computer)
{
    // Ignore updates for computers that aren't ours
    if (computer != m_Computer) {
        return;
    }

    updateFrameLimiterCapabilities();
    updateSleepAction();

    // If the computer has gone offline or we've been unpaired,
    // signal the UI so we can go back to the PC view.
    if (m_Computer->state == NvComputer::CS_OFFLINE ||
            m_Computer->pairState == NvComputer::PS_NOT_PAIRED) {
        emit computerLost();
        return;
    }

    // Which apps count as controls can change once the host has told us
    // what it is, and grouped controls are ordered after the games
    bool controlIdFallback;
    {
        QReadLocker lock(&m_Computer->lock);
        controlIdFallback = m_Computer->otpPairingSupported;
    }
    if (controlIdFallback != m_ControlIdFallback) {
        if (m_GroupHostControls) {
            beginResetModel();
            m_ControlIdFallback = controlIdFallback;
            m_VisibleApps = getVisibleApps(m_AllApps);
            endResetModel();
        }
        else {
            m_ControlIdFallback = controlIdFallback;
        }
    }

    // First, process additions/removals from the app list. This
    // is required because the new game may now be running, so
    // we can't check that first.
    if (computer->appList != m_AllApps) {
        updateAppList(computer->appList);
    }

    // Finally, process changes to the active app
    if (computer->currentGameId != m_CurrentGameId) {
        // First, invalidate the running state of newly running game
        for (int i = 0; i < m_VisibleApps.count(); i++) {
            if (m_VisibleApps[i].id == computer->currentGameId) {
                emit dataChanged(createIndex(i, 0),
                                 createIndex(i, 0),
                                 QVector<int>() << RunningRole);
                break;
            }
        }

        // Next, invalidate the running state of the old game (if it exists)
        if (m_CurrentGameId != 0) {
            for (int i = 0; i < m_VisibleApps.count(); i++) {
                if (m_VisibleApps[i].id == m_CurrentGameId) {
                    emit dataChanged(createIndex(i, 0),
                                     createIndex(i, 0),
                                     QVector<int>() << RunningRole);
                    break;
                }
            }
        }

        // Now update our internal state
        m_CurrentGameId = m_Computer->currentGameId;
    }
}

void AppModel::handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl /* image */)
{
    Q_ASSERT(computer == m_Computer);

    int index = m_VisibleApps.indexOf(app);

    // Make sure we're not delivering a callback to an app that's already been removed
    if (index >= 0) {
        // Let our view know the box art data has changed for this app
        emit dataChanged(createIndex(index, 0),
                         createIndex(index, 0),
                         QVector<int>() << BoxArtRole);
    }
    else {
        qWarning() << "App not found for box art callback:" << app.name;
    }
}
