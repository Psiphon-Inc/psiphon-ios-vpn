#ifndef client_hpp
#define client_hpp

#include <stdio.h>
#include <mutex>
#include "json.hpp"
#include "psicash_types.hpp"

using json = nlohmann::json;

// Types

/*!
Cached client object.
*/
struct client_t {
    balance_t balance;
    std::mutex *access;
};

// JSON

/*
nlohmann JSON de/serializers.
*/
void to_json(json& j, const client_t& c);

#endif /* client_hpp */

