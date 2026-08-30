import * as React from 'react';
import { useEffect, useState } from 'react';
import { Link, NavLink } from 'react-router-dom';
import { useStoreState } from 'easy-peasy';
import { ApplicationStore } from '@/state';
import SearchContainer from '@/components/dashboard/search/SearchContainer';
import http from '@/api/http';
import SpinnerOverlay from '@/components/elements/SpinnerOverlay';
import Avatar from '@/components/Avatar';

const navItems = [
    { to: '/', icon: '🏠', label: 'Home', exact: true },
    { to: '/#servers', icon: '🖥️', label: 'Servers' },
    { to: '/account', icon: '👤', label: 'Account' },
];

export default () => {
    const rootAdmin = useStoreState((state: ApplicationStore) => state.user.data!.rootAdmin);
    const username = useStoreState((state: ApplicationStore) => state.user.data!.username);
    const [isLoggingOut, setIsLoggingOut] = useState(false);
    const [collapsed, setCollapsed] = useState(() => localStorage.getItem('jz-sidebar-collapsed') === '1');
    const [mobileOpen, setMobileOpen] = useState(false);

    useEffect(() => {
        document.body.classList.add('jz-shell');
        document.body.classList.toggle('jz-sidebar-collapsed', collapsed);
        localStorage.setItem('jz-sidebar-collapsed', collapsed ? '1' : '0');

        return () => {
            document.body.classList.remove('jz-shell', 'jz-sidebar-collapsed');
        };
    }, [collapsed]);

    useEffect(() => {
        const close = () => setMobileOpen(false);
        window.addEventListener('resize', close);
        return () => window.removeEventListener('resize', close);
    }, []);

    const onTriggerLogout = () => {
        setIsLoggingOut(true);
        http.post('/auth/logout').finally(() => {
            window.location.href = '/';
        });
    };

    const sidebarWidth = collapsed ? 'w-[72px]' : 'w-[252px]';

    return (
        <>
            <SpinnerOverlay visible={isLoggingOut} />
            <button
                type={'button'}
                aria-label={'Open navigation'}
                className={`jz-mobile-toggle fixed top-4 left-4 z-[80] rounded-xl border border-white/10 bg-[#0A111C]/90 p-3 text-xl shadow-xl backdrop-blur-xl lg:hidden`}
                onClick={() => setMobileOpen(true)}
            >
                ☰
            </button>

            {mobileOpen && (
                <button
                    aria-label={'Close navigation'}
                    className={'fixed inset-0 z-[70] bg-black/60 backdrop-blur-sm lg:hidden'}
                    onClick={() => setMobileOpen(false)}
                />
            )}

            <aside
                className={`jz-sidebar fixed left-0 top-0 z-[75] flex h-screen ${sidebarWidth} flex-col border-r border-white/[.07] bg-[#070D15]/95 px-3 py-4 shadow-2xl backdrop-blur-2xl transition-all duration-300 lg:translate-x-0 ${mobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'}`}
            >
                <div className={'flex items-center justify-between px-2 pb-5'}>
                    <Link to={'/'} className={'flex min-w-0 items-center gap-3 no-underline'}>
                        <img
                            src={'/images/jz-logo.png'}
                            alt={'J&Z Panel'}
                            className={'h-12 w-12 shrink-0 object-contain'}
                        />
                        {!collapsed && (
                            <span className={'truncate text-lg font-bold tracking-tight text-white'}>
                                J&Z <span className={'text-[#08A8FF]'}>Panel</span>
                            </span>
                        )}
                    </Link>
                    <button
                        type={'button'}
                        aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
                        className={'hidden rounded-lg p-2 text-slate-400 transition hover:bg-white/5 hover:text-white lg:block'}
                        onClick={() => setCollapsed((value) => !value)}
                    >
                        {collapsed ? '→' : '←'}
                    </button>
                </div>

                {!collapsed && (
                    <div className={'mb-4 rounded-xl border border-white/[.06] bg-white/[.025] p-3'}>
                        <div className={'text-[10px] font-bold uppercase tracking-[.18em] text-slate-500'}>Workspace</div>
                        <div className={'mt-1 truncate text-sm font-semibold text-slate-200'}>Your hosting hub</div>
                    </div>
                )}

                <nav className={'flex-1 space-y-1 overflow-y-auto'}>
                    {!collapsed && <div className={'px-3 pb-2 pt-2 text-[10px] font-bold uppercase tracking-[.18em] text-slate-500'}>Navigation</div>}
                    {navItems.map((item, index) => (
                        <NavLink
                            key={`${item.label}-${index}`}
                            to={item.to}
                            exact={item.exact}
                            className={'jz-nav-item group flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium text-slate-400 no-underline transition-all duration-200'}
                            activeClassName={'jz-nav-active'}
                            isActive={(match, location) => item.label !== 'Servers' && !!match}
                            onClick={() => setMobileOpen(false)}
                        >
                            <span className={'flex h-7 w-7 shrink-0 items-center justify-center text-lg'}>{item.icon}</span>
                            {!collapsed && <span>{item.label}</span>}
                        </NavLink>
                    ))}

                    <NavLink
                        to={'/account'}
                        className={'jz-nav-item group flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium text-slate-400 no-underline transition-all duration-200'}
                        activeClassName={'jz-nav-active'}
                        isActive={() => false}
                        onClick={() => setMobileOpen(false)}
                    >
                        <span className={'flex h-7 w-7 shrink-0 items-center justify-center text-lg'}>⚙️</span>
                        {!collapsed && <span>Settings</span>}
                    </NavLink>

                    {rootAdmin && (
                        <>
                            {!collapsed && <div className={'px-3 pb-2 pt-6 text-[10px] font-bold uppercase tracking-[.18em] text-slate-500'}>Administration</div>}
                            <a
                                href={'/admin'}
                                className={'jz-nav-item group flex items-center gap-3 rounded-xl px-3 py-3 text-sm font-medium text-slate-400 no-underline transition-all duration-200'}
                                onClick={() => setMobileOpen(false)}
                            >
                                <span className={'flex h-7 w-7 shrink-0 items-center justify-center text-lg'}>🛡️</span>
                                {!collapsed && <span>Administration</span>}
                            </a>
                        </>
                    )}
                </nav>

                <div className={'border-t border-white/[.07] pt-3'}>
                    <div className={'flex items-center gap-3 rounded-xl bg-white/[.025] px-3 py-3'}>
                        <span className={'flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-cyan-400/20 bg-cyan-400/10 text-lg'}>
                            <Avatar.User />
                        </span>
                        {!collapsed && (
                            <div className={'min-w-0 flex-1'}>
                                <div className={'truncate text-sm font-semibold text-slate-200'}>{username}</div>
                                <div className={'text-xs text-slate-500'}>J&Z account</div>
                            </div>
                        )}
                    </div>
                    <div className={`mt-2 flex ${collapsed ? 'justify-center' : 'justify-between'} gap-1`}>
                        <Link to={'/account'} className={'rounded-lg p-2 text-lg no-underline hover:bg-white/5'} title={'Account'}>👤</Link>
                        <button onClick={onTriggerLogout} className={'rounded-lg p-2 text-lg text-slate-400 hover:bg-white/5 hover:text-white'} title={'Sign out'}>🚪</button>
                    </div>
                </div>
            </aside>

            <div className={'jz-topbar fixed left-0 right-0 top-0 z-[60] hidden h-16 items-center justify-between border-b border-white/[.06] bg-[#05090F]/70 px-6 pl-[292px] backdrop-blur-xl lg:flex'}>
                <div className={'flex items-center gap-3'}>
                    <span className={'text-lg'}>✨</span>
                    <span className={'text-sm font-medium text-slate-300'}>J&Z Panel</span>
                </div>
                <div className={'flex items-center gap-3'}>
                    <SearchContainer />
                    <NavLink to={'/account'} className={'rounded-xl p-2 no-underline hover:bg-white/5'} title={'Account'}>👤</NavLink>
                    {rootAdmin && <a href={'/admin'} className={'rounded-xl p-2 no-underline hover:bg-white/5'} title={'Administration'}>🛡️</a>}
                    <button onClick={onTriggerLogout} className={'rounded-xl p-2 text-lg hover:bg-white/5'} title={'Sign out'}>🚪</button>
                </div>
            </div>
        </>
    );
};
