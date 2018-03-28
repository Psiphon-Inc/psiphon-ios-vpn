#include "psicash_client.hpp"

void to_json(json& j, const client_t& c) {
    j = json{{"balance", c.balance}};
}
