import { settled, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { cloneJSON } from "discourse/lib/object";
import { withPluginApi } from "discourse/lib/plugin-api";
import Category from "discourse/models/category";
import Topic from "discourse/models/topic";
import discoveryFixtures from "discourse/tests/fixtures/discovery-fixtures";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const latestTopic = {
  id: 45671,
  category_id: 1,
  title: "The actual latest discussion",
  fancy_title: "The actual latest discussion",
  slug: "actual-latest-discussion",
  bumped_at: "2026-09-23T12:00:00Z",
  last_posted_at: "2026-09-23T12:00:00Z",
  posts_count: 3,
  highest_post_number: 3,
  pinned: false,
  visible: true,
  last_poster_username: "latest_author",
  last_poster: {
    id: 45672,
    username: "latest_author",
    avatar_template: "/letter_avatar_proxy/v4/letter/l/0088cc/{size}.png",
  },
};

for (const mobile of [false, true]) {
  acceptance(
    `Categories with latest topics | ${mobile ? "mobile" : "desktop"}`,
    function (needs) {
      if (mobile) {
        needs.mobileView();
      }
      needs.settings({
        discourse_category_latest_topics_enabled: true,
        desktop_category_page_style: "categories_with_latest_topics",
        mobile_category_page_style: "categories_with_latest_topics",
      });

      let winners;
      let nativeTopics;
      let extraRequests;
      needs.hooks.beforeEach(() => {
        winners = [cloneJSON(latestTopic)];
        nativeTopics = [
          {
            ...latestTopic,
            id: 45673,
            title: "Pinned information topic",
            fancy_title: "Pinned information topic",
            pinned: true,
          },
        ];
        extraRequests = [];
      });
      needs.pretender((server, helper) => {
        server.get("/categories.json", () => {
          const response = cloneJSON(discoveryFixtures["/categories.json"]);
          response.category_list.categories = [
            {
              ...response.category_list.categories[0],
              id: 1,
              num_featured_topics: 0,
              topics: nativeTopics,
              category_latest_topics: winners,
            },
          ];
          return helper.response(response);
        });
        ["/latest.json", "/filter.json"].forEach((path) => {
          server.get(path, (request) => {
            extraRequests.push(request.url);
            return helper.response(500, {});
          });
        });
      });
      needs.hooks.afterEach(function (assert) {
        assert.deepEqual(extraRequests, [], "no supplemental topic requests");
      });

      test("renders the server winner and retains native topics separately", async function (assert) {
        await visit("/categories");
        const category = Category.findById(1);
        const selected = category.featuredTopics[0];
        assert.true(
          selected instanceof Topic,
          "the winner is a native Topic model"
        );
        assert.strictEqual(
          selected.id,
          latestTopic.id,
          "uses the server winner"
        );
        assert.strictEqual(
          category.topics[0].id,
          45673,
          "preserves the featured payload"
        );
        assert
          .dom(`.category-list [data-topic-id="${latestTopic.id}"]`)
          .exists("the latest topic renders");
        assert
          .dom('.category-list [data-topic-id="45673"]')
          .doesNotExist("pins do not render in latest slots");
        category.set("description_excerpt", "Updated category description");
        await settled();
        assert.strictEqual(
          category.featuredTopics[0],
          selected,
          "retains topic identity across renders"
        );
      });

      test("an empty latest pool never falls back to a pin", async function (assert) {
        winners = [];
        await visit("/categories");
        assert.deepEqual(
          Category.findById(1).featuredTopics,
          [],
          "keeps the latest slot empty"
        );
        assert
          .dom('.category-list [data-topic-id="45673"]')
          .doesNotExist("the old featured pin stays out");
      });

      test("a fresh category response replaces the winner", async function (assert) {
        await visit("/categories");
        const category = Category.findById(1);
        category.set("category_latest_topics", [
          {
            ...latestTopic,
            id: 45674,
            title: "Another discussion",
            fancy_title: "Another discussion",
          },
        ]);
        await settled();
        assert.strictEqual(
          category.featuredTopics[0].id,
          45674,
          "uses the refreshed latest payload"
        );
        assert
          .dom('.category-list [data-topic-id="45674"]')
          .exists("the refreshed topic renders");
      });

      test("featured layout on this device keeps the native topic", async function (assert) {
        const siteSettings = this.container.lookup("service:site-settings");
        siteSettings[
          mobile ? "mobile_category_page_style" : "desktop_category_page_style"
        ] = "categories_with_featured_topics";
        await visit("/categories");
        assert.strictEqual(
          Category.findById(1).featuredTopics[0].id,
          45673,
          "the other layout remains independent"
        );
        assert
          .dom('.category-list [data-topic-id="45673"]')
          .exists("native featured behavior is retained");
      });

      test("category routes retain their independently configured featured topics", async function (assert) {
        await visit("/categories");
        const category = Category.findById(1);
        assert.strictEqual(category.featuredTopics[0].id, latestTopic.id);

        await visit("/c/bug/1");
        assert.false(category.categoryLatestTopicsActive);
        assert.strictEqual(
          category.featuredTopics[0].id,
          45673,
          "a category route keeps its native featured pool"
        );

        await visit("/categories");
        assert.strictEqual(
          category.featuredTopics[0].id,
          latestTopic.id,
          "returning to the homepage restores the latest layout"
        );
      });

      test("themes can preserve their featured selection outside this layout", async function (assert) {
        const siteSettings = this.container.lookup("service:site-settings");
        siteSettings[
          mobile ? "mobile_category_page_style" : "desktop_category_page_style"
        ] = "categories_with_featured_topics";
        withPluginApi((api) => {
          api.registerValueTransformer(
            "category-latest-topics-featured-fallback",
            ({ context }) => {
              assert.strictEqual(context.category.id, 1);
              return [];
            }
          );
        });
        await visit("/categories");
        assert.deepEqual(Category.findById(1).featuredTopics, []);
        assert.dom('.category-list [data-topic-id="45673"]').doesNotExist();
      });
    }
  );
}
