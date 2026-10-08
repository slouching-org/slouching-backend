//! Small, transport-independent pieces of the future peer core.
//! This is a policy gate for already authenticated MLS commits, not MLS itself.

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommitEnvelope {
    pub group_id: String,
    pub author_device: String,
    pub parent_epoch: u64,
    pub parent_hash: String,
    pub commit_hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CommitError {
    WrongGroup,
    UnauthorizedCommitter,
    MissingPredecessor,
    WrongParent,
    Equivocation,
    Quarantined,
    EmptyHash,
    EpochOverflow,
}

#[derive(Debug, Clone)]
pub struct GroupChain {
    group_id: String,
    designated_committer: String,
    epoch: u64,
    head_hash: String,
    accepted: BTreeMap<u64, String>,
    quarantined: bool,
}

impl GroupChain {
    /// The creation policy and genesis hash must come from authenticated MLS state.
    pub fn new(group_id: String, designated_committer: String, genesis_hash: String) -> Self {
        let mut accepted = BTreeMap::new();
        accepted.insert(0, genesis_hash.clone());
        Self {
            group_id,
            designated_committer,
            epoch: 0,
            head_hash: genesis_hash,
            accepted,
            quarantined: false,
        }
    }

    pub fn epoch(&self) -> u64 {
        self.epoch
    }

    pub fn is_quarantined(&self) -> bool {
        self.quarantined
    }

    /// Call only after checking the author signature and MLS Commit cryptography.
    /// A matching replay is harmless; two different hashes at one epoch quarantine the group.
    pub fn accept_verified(&mut self, commit: &CommitEnvelope) -> Result<(), CommitError> {
        if self.quarantined {
            return Err(CommitError::Quarantined);
        }
        if commit.group_id != self.group_id {
            return Err(CommitError::WrongGroup);
        }
        if commit.author_device != self.designated_committer {
            return Err(CommitError::UnauthorizedCommitter);
        }
        if commit.parent_hash.is_empty() || commit.commit_hash.is_empty() {
            return Err(CommitError::EmptyHash);
        }
        let resulting_epoch = commit
            .parent_epoch
            .checked_add(1)
            .ok_or(CommitError::EpochOverflow)?;

        if commit.parent_epoch < self.epoch {
            if self.accepted.get(&commit.parent_epoch) != Some(&commit.parent_hash) {
                return Err(CommitError::WrongParent);
            }
            return match self.accepted.get(&resulting_epoch) {
                Some(hash) if hash == &commit.commit_hash => Ok(()),
                Some(_) => {
                    self.quarantined = true;
                    Err(CommitError::Equivocation)
                }
                None => Err(CommitError::MissingPredecessor),
            };
        }
        if commit.parent_epoch > self.epoch {
            return Err(CommitError::MissingPredecessor);
        }
        if commit.parent_hash != self.head_hash {
            return Err(CommitError::WrongParent);
        }

        self.epoch = resulting_epoch;
        self.head_hash.clone_from(&commit.commit_hash);
        self.accepted
            .insert(resulting_epoch, commit.commit_hash.clone());
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chain() -> GroupChain {
        GroupChain::new("crew".into(), "device-a".into(), "genesis".into())
    }

    fn commit(parent_epoch: u64, parent_hash: &str, hash: &str) -> CommitEnvelope {
        CommitEnvelope {
            group_id: "crew".into(),
            author_device: "device-a".into(),
            parent_epoch,
            parent_hash: parent_hash.into(),
            commit_hash: hash.into(),
        }
    }

    #[test]
    fn one_committer_and_linear_predecessors() {
        let mut group = chain();
        let mut unauthorized = commit(0, "genesis", "one");
        unauthorized.author_device = "device-b".into();
        assert_eq!(
            group.accept_verified(&unauthorized),
            Err(CommitError::UnauthorizedCommitter)
        );
        assert_eq!(
            group.accept_verified(&commit(1, "one", "two")),
            Err(CommitError::MissingPredecessor)
        );
        assert_eq!(
            group.accept_verified(&commit(0, "other", "one")),
            Err(CommitError::WrongParent)
        );
        group.accept_verified(&commit(0, "genesis", "one")).unwrap();
        group.accept_verified(&commit(1, "one", "two")).unwrap();
        assert_eq!(group.epoch(), 2);
    }

    #[test]
    fn duplicate_is_safe_but_fork_quarantines() {
        let mut group = chain();
        group.accept_verified(&commit(0, "genesis", "one")).unwrap();
        group.accept_verified(&commit(0, "genesis", "one")).unwrap();
        assert_eq!(
            group.accept_verified(&commit(0, "other", "one")),
            Err(CommitError::WrongParent)
        );
        assert_eq!(
            group.accept_verified(&commit(0, "genesis", "other")),
            Err(CommitError::Equivocation)
        );
        assert!(group.is_quarantined());
        assert_eq!(
            group.accept_verified(&commit(1, "one", "two")),
            Err(CommitError::Quarantined)
        );
    }
}
