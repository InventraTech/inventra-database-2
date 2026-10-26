// Seção 11 de neo4j/docs/COBERTURA_FORNECEDORES.md — seed demonstrativo.
// Requisição #842 (cozinha 12): Arroz 20 un.; Óleo 10 un.; Feijão 5 un.; Leite 12 un.

MERGE (r:Requisition {id:842}) SET r.kitchenId=12, r.status='UNDER_REVIEW'
MERGE (a:Product {id:10}) SET a.name='Arroz', a.active=true
MERGE (o:Product {id:11}) SET o.name='Óleo', o.active=true
MERGE (f:Product {id:12}) SET f.name='Feijão', f.active=true
MERGE (l:Product {id:13}) SET l.name='Leite', l.active=true
MERGE (r)-[:REQUESTS {itemId:1, quantity:20}]->(a)
MERGE (r)-[:REQUESTS {itemId:2, quantity:10}]->(o)
MERGE (r)-[:REQUESTS {itemId:3, quantity:5}]->(f)
MERGE (r)-[:REQUESTS {itemId:4, quantity:12}]->(l);

// Fornecedores e vínculos SUPPLIES, conforme a matriz da seção 11 (preço de referência / prazo em dias).
// O PDF só fixa o id do Alfa (31, no contrato REST); os ids 32 (Beta) e 33 (Gama) foram atribuídos aqui.
MERGE (alfa:Supplier {id:31}) SET alfa.legalName='Distribuidora Alfa', alfa.rating=5, alfa.active=true
MERGE (beta:Supplier {id:32}) SET beta.legalName='Beta', beta.rating=4, beta.active=true
MERGE (gama:Supplier {id:33}) SET gama.legalName='Gama', gama.rating=3, gama.active=true;

MATCH (alfa:Supplier {id:31}), (beta:Supplier {id:32}), (gama:Supplier {id:33}),
      (arroz:Product {id:10}), (oleo:Product {id:11}), (feijao:Product {id:12}), (leite:Product {id:13})
MERGE (alfa)-[r1:SUPPLIES]->(arroz)  SET r1.referencePrice=18.50, r1.leadTimeDays=2
MERGE (alfa)-[r2:SUPPLIES]->(oleo)   SET r2.referencePrice=7.65,  r2.leadTimeDays=3
MERGE (alfa)-[r3:SUPPLIES]->(feijao) SET r3.referencePrice=8.00,  r3.leadTimeDays=2
MERGE (beta)-[r4:SUPPLIES]->(oleo)   SET r4.referencePrice=7.20,  r4.leadTimeDays=5
MERGE (beta)-[r5:SUPPLIES]->(leite)  SET r5.referencePrice=5.50,  r5.leadTimeDays=4
MERGE (gama)-[r6:SUPPLIES]->(arroz)  SET r6.referencePrice=17.90, r6.leadTimeDays=7
MERGE (gama)-[r7:SUPPLIES]->(feijao) SET r7.referencePrice=7.80,  r7.leadTimeDays=6
MERGE (gama)-[r8:SUPPLIES]->(leite)  SET r8.referencePrice=5.70,  r8.leadTimeDays=7;
