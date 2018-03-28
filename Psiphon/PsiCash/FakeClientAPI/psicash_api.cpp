#include "psicash_api.hpp"
#include "psicash_client.hpp"
#include "psicash_types.hpp"
#include "json.hpp"
#include <chrono>
#include <iostream>
#include <thread>

using json = nlohmann::json;

/*****************************************************************************************************************/
/***                                                                                                           ***/
/*** Warning: this code is PoC at best and is intended only for exercising the PsiCash UI.                     ***/
/*** No effort has been made to prevent race conditions, check if allocations fail, prevent memory leaks, etc. ***/
/***                                                                                                           ***/
/*****************************************************************************************************************/

// Forward declarations

char *to_c_str(const std::string str);
void start_demo_mode(void *client);
void demo_mode(client_t *client);
void randomized_client_update(void *client);

// Helpers

char *to_c_str(const std::string str) {
    const char *c = str.c_str();
    char *s = (char *)malloc(sizeof(char) * strlen(c) + 1);
    memcpy(s, c,sizeof(char) * strlen(c) + 1);
    return s;
}

client_t *construct_client() {
    client_t *c = (client_t *)malloc(sizeof(client_t));
    c->balance = 0;
    c->access = new std::mutex;
    return c;
}

char *get_client_status(void *client) {
    client_t *c = (client_t*)client;
    json j = *c;
    return to_c_str(j.dump());
}

void demo_mode(client_t *client) {
    client_t *c = (client_t*)client;
    for (;;) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        if (client) {
            randomized_client_update(c);
        }
    }
}

void randomized_client_update(void *client) {
    client_t *c = (client_t*)client;
    c->access->lock();
    int m = rand()%10;
    u_int64_t inc = 0.03e9 * (rand()%1000) * m;
    c->balance += inc;
    print_client(c);
    c->access->unlock();
}

// Exposed

void *new_client() {
    client_t *c = construct_client();
    return (void*)c;
}

void free_client(void *client) {
    client_t *c = (client_t*)client;
    free(c);
}

u_int64_t get_client_balance(void *client) {
    client_t *c = (client_t*)client;
    return c->balance;
}

void make_client_purchase(void *client, cash_client_balance_t price) {
    client_t *c = (client_t*)client;
    c->access->lock();
    assert (c->balance >= price);
    c->balance -= price;
    c->access->unlock();
}

void start_demo_mode(void *client) {
    client_t *c = (client_t*)client;
    std::thread t (demo_mode, c);
    t.detach();
}

void print_client(void *client) {
    client_t *c = (client_t*)client;
    char *status = get_client_status(c);
    std::cout << status << "\n";
    free(status);
    return;
}
