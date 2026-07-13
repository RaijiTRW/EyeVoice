"use client";

import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { supabase } from "@/lib/supabase";
import { useUser } from "@/lib/useUser";

type AdminAccessState = {
  isAdmin: boolean;
  loading: boolean;
  refresh: () => void;
};

const AdminAccessContext = createContext<AdminAccessState>({
  isAdmin: false,
  loading: true,
  refresh: () => undefined,
});

export function AdminAccessProvider({ children }: { children: ReactNode }) {
  const { user, loading: userLoading } = useUser();
  const [isAdmin, setIsAdmin] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    let cancelled = false;
    if (userLoading) return;
    if (!user) {
      const timer = window.setTimeout(() => {
        setIsAdmin(false);
        setLoading(false);
      }, 0);
      return () => window.clearTimeout(timer);
    }

    supabase.rpc("get_my_admin_status").then(({ data, error }) => {
      if (cancelled) return;
      setIsAdmin(!error && data === true);
      setLoading(false);
    });

    return () => {
      cancelled = true;
    };
  }, [user, userLoading, refreshKey]);

  const value = useMemo(
    () => ({ isAdmin, loading, refresh: () => setRefreshKey((value) => value + 1) }),
    [isAdmin, loading],
  );

  return <AdminAccessContext.Provider value={value}>{children}</AdminAccessContext.Provider>;
}

export function useAdminAccess() {
  return useContext(AdminAccessContext);
}
