use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use svn_backend::{StatusOptions, StatusProvider, SvnError, SvnStatusEntry, SvnStatusKind};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BadgeEntry {
    pub status: SvnStatusKind,
    pub props_modified: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BadgeSnapshot {
    pub root: PathBuf,
    pub generated_at: SystemTime,
    pub entries: BTreeMap<PathBuf, BadgeEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RefreshPlan {
    pub root: PathBuf,
    pub full_refresh: bool,
    pub dirty_paths: Vec<PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EngineConfig {
    pub badge_entry_limit: usize,
    pub changed_path_batch_size: usize,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            badge_entry_limit: 4_096,
            changed_path_batch_size: 256,
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct DirtyRootState {
    force_full_refresh: bool,
    dirty_paths: BTreeSet<PathBuf>,
}

pub struct StatusEngine<P> {
    provider: P,
    config: EngineConfig,
    snapshots: BTreeMap<PathBuf, BadgeSnapshot>,
    dirty_roots: BTreeMap<PathBuf, DirtyRootState>,
}

impl<P> StatusEngine<P> {
    pub fn new(provider: P) -> Self {
        Self::with_config(provider, EngineConfig::default())
    }

    pub fn with_config(provider: P, config: EngineConfig) -> Self {
        Self {
            provider,
            config,
            snapshots: BTreeMap::new(),
            dirty_roots: BTreeMap::new(),
        }
    }

    pub fn snapshot(&self, root: &Path) -> Option<&BadgeSnapshot> {
        self.snapshots.get(root)
    }

    pub fn pending_roots(&self) -> Vec<PathBuf> {
        self.dirty_roots.keys().cloned().collect()
    }
}

impl<P: StatusProvider> StatusEngine<P> {
    pub fn mark_dirty<I, T>(&mut self, root: &Path, paths: I)
    where
        I: IntoIterator<Item = T>,
        T: AsRef<Path>,
    {
        let state = self
            .dirty_roots
            .entry(root.to_path_buf())
            .or_insert_with(DirtyRootState::default);

        for path in paths {
            if state.force_full_refresh {
                continue;
            }

            state.dirty_paths.insert(path.as_ref().to_path_buf());
            if state.dirty_paths.len() > self.config.changed_path_batch_size {
                state.force_full_refresh = true;
                state.dirty_paths.clear();
            }
        }
    }

    pub fn schedule_full_refresh(&mut self, root: &Path) {
        let state = self
            .dirty_roots
            .entry(root.to_path_buf())
            .or_insert_with(DirtyRootState::default);
        state.force_full_refresh = true;
        state.dirty_paths.clear();
    }

    pub fn plan_refresh(&self, root: &Path) -> RefreshPlan {
        let state = self.dirty_roots.get(root).cloned().unwrap_or_default();
        let dirty_paths = state.dirty_paths.into_iter().collect::<Vec<_>>();
        let full_refresh = state.force_full_refresh || dirty_paths.is_empty();

        RefreshPlan {
            root: root.to_path_buf(),
            full_refresh,
            dirty_paths,
        }
    }

    pub fn refresh_root(&mut self, root: &Path) -> Result<BadgeSnapshot, SvnError> {
        self.refresh_root_with_options(root, &StatusOptions::default())
    }

    pub fn refresh_root_with_options(
        &mut self,
        root: &Path,
        options: &StatusOptions,
    ) -> Result<BadgeSnapshot, SvnError> {
        let plan = self.plan_refresh(root);
        let status_entries = self.provider.status(root, options)?;
        let snapshot = build_badge_snapshot(root, status_entries, self.config.badge_entry_limit);

        self.snapshots.insert(root.to_path_buf(), snapshot.clone());
        self.dirty_roots.remove(root);

        if !plan.full_refresh && plan.dirty_paths.is_empty() {
            self.schedule_full_refresh(root);
        }

        Ok(snapshot)
    }
}

fn build_badge_snapshot(
    root: &Path,
    status_entries: Vec<SvnStatusEntry>,
    limit: usize,
) -> BadgeSnapshot {
    let mut entries = BTreeMap::new();

    for entry in status_entries
        .into_iter()
        .filter(|entry| entry.status.is_dirty() || entry.props_modified)
    {
        entries.insert(
            entry.path,
            BadgeEntry {
                status: entry.status,
                props_modified: entry.props_modified,
            },
        );
        if entries.len() >= limit {
            break;
        }
    }

    BadgeSnapshot {
        root: root.to_path_buf(),
        generated_at: SystemTime::now(),
        entries,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use svn_backend::{SvnStatusEntry, SvnStatusKind};

    struct FakeProvider {
        entries: Vec<SvnStatusEntry>,
    }

    impl StatusProvider for FakeProvider {
        fn status(
            &self,
            _root: &Path,
            _options: &StatusOptions,
        ) -> Result<Vec<SvnStatusEntry>, SvnError> {
            Ok(self.entries.clone())
        }
    }

    #[test]
    fn batch_overflow_promotes_root_to_full_refresh() {
        let provider = FakeProvider {
            entries: Vec::new(),
        };
        let mut engine = StatusEngine::with_config(
            provider,
            EngineConfig {
                badge_entry_limit: 16,
                changed_path_batch_size: 2,
            },
        );
        let root = Path::new("/repo");
        engine.mark_dirty(root, ["a", "b", "c"]);

        let plan = engine.plan_refresh(root);
        assert!(plan.full_refresh);
        assert!(plan.dirty_paths.is_empty());
    }

    #[test]
    fn refresh_root_keeps_only_dirty_badge_entries() {
        let provider = FakeProvider {
            entries: vec![
                SvnStatusEntry {
                    path: PathBuf::from("/repo/src/main.rs"),
                    status: SvnStatusKind::Modified,
                    props_modified: false,
                },
                SvnStatusEntry {
                    path: PathBuf::from("/repo/README.md"),
                    status: SvnStatusKind::Normal,
                    props_modified: false,
                },
                SvnStatusEntry {
                    path: PathBuf::from("/repo/tmp.txt"),
                    status: SvnStatusKind::Unversioned,
                    props_modified: false,
                },
            ],
        };
        let mut engine = StatusEngine::new(provider);
        let root = Path::new("/repo");
        engine.schedule_full_refresh(root);

        let snapshot = engine.refresh_root(root).unwrap();

        assert_eq!(snapshot.entries.len(), 2);
        assert_eq!(
            snapshot
                .entries
                .get(Path::new("/repo/src/main.rs"))
                .map(|entry| &entry.status),
            Some(&SvnStatusKind::Modified)
        );
        assert_eq!(
            snapshot
                .entries
                .get(Path::new("/repo/tmp.txt"))
                .map(|entry| &entry.status),
            Some(&SvnStatusKind::Unversioned)
        );
        assert!(engine.pending_roots().is_empty());
    }

    #[test]
    fn refresh_root_keeps_property_only_changes() {
        let provider = FakeProvider {
            entries: vec![SvnStatusEntry {
                path: PathBuf::from("/repo/project.xcodeproj"),
                status: SvnStatusKind::Normal,
                props_modified: true,
            }],
        };
        let mut engine = StatusEngine::new(provider);
        let root = Path::new("/repo");
        engine.schedule_full_refresh(root);

        let snapshot = engine.refresh_root(root).unwrap();
        let entry = snapshot.entries.get(Path::new("/repo/project.xcodeproj"));

        assert_eq!(snapshot.entries.len(), 1);
        assert_eq!(entry.map(|item| item.props_modified), Some(true));
        assert_eq!(entry.map(|item| &item.status), Some(&SvnStatusKind::Normal));
    }
}
