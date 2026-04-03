import { Plugin } from 'release-it';
import semver from 'semver';

/**
 * Plugin that allows "post-release" prereleases (e.g., 0.0.1 -> 0.0.1-dev.0)
 * by bypassing semver's gte check. Standard semver considers 0.0.1-dev.0 < 0.0.1,
 * but this plugin accepts any valid semver version as the target.
 */
class ForceVersionPlugin extends Plugin {
  getIncrementedVersionCI({ increment }) {
    if (semver.valid(increment)) {
      return increment;
    }
  }

  getIncrementedVersion({ increment }) {
    if (semver.valid(increment)) {
      return increment;
    }
  }
}

export default ForceVersionPlugin;
