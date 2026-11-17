#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <rime_api.h>

static int deployment_failed;

static void notification(void *context, RimeSessionId session,
                         const char *type, const char *value) {
  if (!strcmp(type, "deploy") && !strcmp(value, "failure")) {
    deployment_failed = 1;
  }
}

int main(int argc, char **argv) {
  assert(argc == 4);
  RimeApi *api = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.distribution_code_name = argv[3];
  traits.app_name = "rime.state-test";
  traits.min_log_level = 2;
  traits.log_dir = "";
  api->setup(&traits);
  api->set_notification_handler(notification, NULL);
  api->initialize(&traits);
  api->start_maintenance(False);
  api->join_maintenance_thread();
  assert(!deployment_failed);

  RimeSessionId session = api->create_session();
  assert(session);
  assert(api->select_schema(session, "wanxiang"));
  assert(!api->get_option(session, "ascii_mode"));
  for (const char *key = "nihao"; *key; ++key) {
    assert(api->process_key(session, *key, 0));
  }
  RIME_STRUCT(RimeContext, context);
  assert(api->get_context(session, &context));
  assert(context.menu.num_candidates > 0);
  assert(strstr(context.menu.candidates[0].text, "\xe4\xbd\xa0\xe5\xa5\xbd"));
  printf("nihao candidate: %s\n", context.menu.candidates[0].text);
  api->free_context(&context);
  api->destroy_session(session);
  api->finalize();
  return 0;
}
