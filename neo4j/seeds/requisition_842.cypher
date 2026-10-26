// Massa de teste da especificação (seção 11): 1 requisição, 4 produtos e 3 fornecedores.
// Gera cobertura parcial empatada, cobertura menor e lacuna, evitando um teste trivial.
//
//   Fornecedor        Arroz          Óleo          Feijão        Leite         Cobertura
//   Alfa (rating 5)   R$ 18,50 / 2d  R$ 7,65 / 3d  R$ 8,00 / 2d  —             3/4 = 75%
//   Beta (rating 4)   —              R$ 7,20 / 5d  —             R$ 5,50 / 4d  2/4 = 50%
//   Gama (rating 3)   R$ 17,90 / 7d  —             R$ 7,80 / 6d  R$ 5,70 / 7d  3/4 = 75%
//
// Demanda da #842 (cozinha 12): Arroz 20 un.; Óleo 10 un.; Feijão 5 un.; Leite 12 un.
// Esperado (tests/check_supplier_coverage.sh confere):
//   1 Alfa  Arroz, Óleo, Feijão  falta Leite          R$ 486,50  3 dias
//   2 Gama  Arroz, Feijão, Leite falta Óleo           R$ 465,40  7 dias
//   3 Beta  Óleo, Leite          falta Arroz, Feijão  R$ 138,00  5 dias
// Alfa vem antes de Gama: ambos cobrem 75%, mas Alfa tem prazo máximo de 3 dias contra 7.
//
// IDs fictícios: este arquivo é fixture de teste, não carga de produção (para isso, seeds/seed.ipynb).
// Idempotente: MERGE pelas chaves; rodar duas vezes não muda contagens nem propriedades.

MERGE (r:Requisition {id: 842})
SET r.kitchenId = 12, r.type = 'PURCHASE', r.status = 'UNDER_REVIEW'

MERGE (a:Product {id: 10}) SET a.name = 'Arroz', a.active = true
MERGE (o:Product {id: 11}) SET o.name = 'Óleo', o.active = true
MERGE (f:Product {id: 12}) SET f.name = 'Feijão', f.active = true
MERGE (l:Product {id: 13}) SET l.name = 'Leite', l.active = true

MERGE (r)-[q1:REQUESTS {itemId: 1}]->(a) SET q1.quantity = 20
MERGE (r)-[q2:REQUESTS {itemId: 2}]->(o) SET q2.quantity = 10
MERGE (r)-[q3:REQUESTS {itemId: 3}]->(f) SET q3.quantity = 5
MERGE (r)-[q4:REQUESTS {itemId: 4}]->(l) SET q4.quantity = 12

MERGE (alfa:Supplier {id: 31}) SET alfa.legalName = 'Distribuidora Alfa', alfa.rating = 5, alfa.active = true
MERGE (beta:Supplier {id: 32}) SET beta.legalName = 'Beta', beta.rating = 4, beta.active = true
MERGE (gama:Supplier {id: 33}) SET gama.legalName = 'Gama', gama.rating = 3, gama.active = true

MERGE (alfa)-[s1:SUPPLIES]->(a) SET s1.supplierCode = 'ALF-010', s1.referencePrice = 18.50, s1.leadTimeDays = 2
MERGE (alfa)-[s2:SUPPLIES]->(o) SET s2.supplierCode = 'ALF-011', s2.referencePrice = 7.65, s2.leadTimeDays = 3
MERGE (alfa)-[s3:SUPPLIES]->(f) SET s3.supplierCode = 'ALF-012', s3.referencePrice = 8.00, s3.leadTimeDays = 2

MERGE (beta)-[s4:SUPPLIES]->(o) SET s4.supplierCode = 'BET-011', s4.referencePrice = 7.20, s4.leadTimeDays = 5
MERGE (beta)-[s5:SUPPLIES]->(l) SET s5.supplierCode = 'BET-013', s5.referencePrice = 5.50, s5.leadTimeDays = 4

MERGE (gama)-[s6:SUPPLIES]->(a) SET s6.supplierCode = 'GAM-010', s6.referencePrice = 17.90, s6.leadTimeDays = 7
MERGE (gama)-[s7:SUPPLIES]->(f) SET s7.supplierCode = 'GAM-012', s7.referencePrice = 7.80, s7.leadTimeDays = 6
MERGE (gama)-[s8:SUPPLIES]->(l) SET s8.supplierCode = 'GAM-013', s8.referencePrice = 5.70, s8.leadTimeDays = 7;
