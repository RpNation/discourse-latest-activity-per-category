# Categories with latest topics

Adds **Categories with latest topics** to Discourse's desktop and mobile category-page layout settings. Each category row shows the visible, unpinned topic with the newest activity, including eligible topics in its subcategories.

Discourse's featured-topic pool can fill with pinned informational topics. Sorting that small pool in a theme cannot find discussions omitted from it. This plugin queries the eligible topics directly and sends the result with the existing category response.

## Setup

1. Install the complete plugin directory as `plugins/discourse-category-latest-topics`, run its migration, and restart Discourse.
2. Enable `discourse_category_latest_topics_enabled`.
3. Select **Categories with latest topics** for `desktop_category_page_style`, `mobile_category_page_style`, or both.
4. Put `categories` first in `top_menu` if Categories should be the homepage.

Use a current Discourse release. Developed against core `c9d27d5d2e` and its modern model extension API.

The native category-row renderer is reused, including last-poster information, unread state, and plugin outlets. The RpNation theme component adds its existing compact styling and virtual Hosted Projects groups; use the accompanying theme update to recognize the new layout. The plugin also works with Discourse's standard theme and adds no RpNation colors or graphics.

## Selection rules

- Latest means greatest `bumped_at`, with the topic ID breaking ties. A reply can make an older discussion the latest.
- Pinned topics are excluded, including global pins and pins a reader has dismissed. Category-description topics are excluded too.
- Discourse's native topic query enforces permissions, visibility, deleted-topic exclusion, personal-message exclusion, shared-draft rules, and muted topics/categories/tags.
- A parent can show the latest eligible discussion from an accessible descendant. Category nesting remains unchanged.
- A category without an eligible discussion has an empty latest slot. It does not fall back to a pinned topic.
- One result is returned per category, independently of `num_featured_topics` and the featured-topic count setting.
- Category order and the native large-category-site layout fallback are unchanged.

The plugin does not unpin topics, edit the featured-topic cache, or change topic lists inside categories.
Category pages keep their independently selected subcategory layout; the new
style applies to the Categories page and native subcategory-directory route.

## Implementation

The existing category response gains `category_latest_topics`, an array containing zero or one topic serialized by Discourse's native `ListableTopicSerializer`. The original `topics` array stays intact, so desktop and mobile can choose different layouts. The selected layout hydrates the separate result into native Topic models, preserving topic identity between renders.

The query uses bounded category-descendant searches and one indexed latest-topic candidate per descendant, then selects the newest candidate for each displayed row. It does not fetch the whole topic history into Ruby. A concurrent partial index supports the activity lookup on eligible topics. Plugin migrations must finish before enabling the feature on a production-sized site.

No extra HTTP requests, scheduled jobs, or rebakes are required. Refreshing the Categories page fetches the current selection; this does not add live push updates.

Discourse has no public registry for extra category layouts in this version. The plugin uses small, scoped extensions to the two enum classes, CategoryList initialization, and the CategoriesDisplay style getter. Existing behavior is retained outside the selected layout. These extension points require compatibility checks when upgrading core.

Themes that customize the category model's `featuredTopics` getter can register
the `category-latest-topics-featured-fallback` value transformer to preserve
their selection outside this layout regardless of initializer order. It receives
the native featured array and `{ category }`; the RpNation theme uses this hook.

Before removing the plugin, switch both category page styles back to native values. Disabling it while the new style remains selected falls back to Categories only.

## Development

Generated using Discourse's official plugin scaffold and reusable CI workflow.

```sh
LOAD_PLUGINS=1 bin/rspec plugins/discourse-category-latest-topics/spec
bin/qunit --standalone --target discourse-category-latest-topics
bin/lint --fix plugins/discourse-category-latest-topics/path/to/changed-file
```
