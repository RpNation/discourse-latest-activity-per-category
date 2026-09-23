import { MAX_UNOPTIMIZED_CATEGORIES } from "discourse/lib/constants";
import Topic from "discourse/models/topic";

export const LATEST_CATEGORY_STYLE = "categories_with_latest_topics";

const topicArrays = new WeakMap();

export function latestCategoryTopicsActive(siteSettings, site, router) {
  if (
    !siteSettings.discourse_category_latest_topics_enabled ||
    site.categories.length > MAX_UNOPTIMIZED_CATEGORIES ||
    !["discovery.categories", "discovery.subcategories"].includes(
      router.currentRouteName
    )
  ) {
    return false;
  }

  const style = site.mobileView
    ? siteSettings.mobile_category_page_style
    : siteSettings.desktop_category_page_style;
  return style === LATEST_CATEGORY_STYLE;
}

export function hydrateLatestTopics(source) {
  if (!Array.isArray(source)) {
    return [];
  }

  let topics = topicArrays.get(source);
  if (!topics) {
    topics = source.map((topic) =>
      topic instanceof Topic ? topic : Topic.create(topic)
    );
    topicArrays.set(source, topics);
  }
  return topics;
}
