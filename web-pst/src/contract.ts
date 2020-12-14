export interface Contract {
  name: string;
  balances: Record<string, number>;
  settings: (string | number)[];
  ticker: string;
}
