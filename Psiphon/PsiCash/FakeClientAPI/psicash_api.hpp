#ifndef psicash_hpp
#define psicash_hpp

#include <stdio.h>
#include "psicash_types.hpp"

void*                 new_client(void);
void                  free_client(void *client);
cash_client_balance_t get_client_balance(void *client);
void                  make_client_purchase(void *client, cash_client_balance_t price);
void                  start_demo_mode(void *client);
void                  print_client(void *client);

#endif /* psicash_hpp */
