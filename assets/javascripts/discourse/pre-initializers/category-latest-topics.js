import { getOwnerWithFallback } from "discourse/lib/get-owner";
import { withPluginApi } from "discourse/lib/plugin-api";
import { applyValueTransformer } from "discourse/lib/transformer";
import {
  hydrateLatestTopics,
  LATEST_CATEGORY_STYLE,
  latestCategoryTopicsActive,
} from "../lib/category-latest-topics";

export default {
  name: "category-latest-topics",
  before: ["freeze-valid-transformers", "inject-discourse-objects"],

  initialize() {
    withPluginApi((api) => {
      api.addValueTransformerName("category-latest-topics-featured-fallback");

      api.addModelField("category", "category_latest_topics", {
        defaultValue: null,
      });

      api.addModelGetter("category", "categoryLatestTopicsActive", function () {
        const owner = getOwnerWithFallback(this);
        return latestCategoryTopicsActive(
          owner.lookup("service:site-settings"),
          owner.lookup("service:site"),
          owner.lookup("service:router")
        );
      });

      api.addModelGetter("category", "latestTopics", function () {
        return hydrateLatestTopics(this.category_latest_topics);
      });

      api.addModelGetter("category", "featuredTopics", function () {
        if (this.categoryLatestTopicsActive) {
          return this.latestTopics;
        }
        return applyValueTransformer(
          "category-latest-topics-featured-fallback",
          this.topics?.slice(0, this.num_featured_topics || 2),
          { category: this }
        );
      });

      api.modifyClass(
        "component:discovery/categories-display",
        (Superclass) =>
          class extends Superclass {
            get style() {
              const style = super.style;
              if (style !== LATEST_CATEGORY_STYLE) {
                return style;
              }

              return this.siteSettings.discourse_category_latest_topics_enabled
                ? "categories_with_featured_topics"
                : "categories_only";
            }
          }
      );
    });
  },
};
